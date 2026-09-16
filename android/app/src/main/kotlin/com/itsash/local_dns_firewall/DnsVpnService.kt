package com.itsash.local_dns_firewall

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import com.itsash.local_dns_firewall.dns.DnsCache
import com.itsash.local_dns_firewall.dns.DnsPacketParser
import com.itsash.local_dns_firewall.dns.DnsResolver
import com.itsash.local_dns_firewall.dns.UdpDnsResolver
import com.itsash.local_dns_firewall.rules.RuleAction
import com.itsash.local_dns_firewall.rules.RuleEngine
import com.itsash.local_dns_firewall.rules.RuleMatch
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

class DnsVpnService : VpnService() {

    companion object {
        private const val TAG = "DnsVpnService"
        private const val CHANNEL_ID = "dns_firewall_protection"
        private const val NOTIF_ID = 1
        const val ACTION_START = "com.itsash.local_dns_firewall.START"
        const val ACTION_STOP = "com.itsash.local_dns_firewall.STOP"

        @Volatile var running: Boolean = false
            private set
        @Volatile var lastError: String? = null
            private set

        val queryCount = AtomicLong(0)
        val blockedCount = AtomicLong(0)
        val allowedCount = AtomicLong(0)
        val cacheHits = AtomicLong(0)
        val cacheMisses = AtomicLong(0)
        val ruleEngine: RuleEngine = RuleEngine()
        val dnsCache: DnsCache = DnsCache()

        @Volatile var currentResolverName: String = "System default"
        @Volatile var upstreamHost: String = "1.1.1.1"
        @Volatile var upstreamPort: Int = 53
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    private val runningFlag = AtomicBoolean(false)

    // Live log sink — called from the VPN thread; listeners are set by the platform channel.
    @Volatile var logSink: ((QueryLogEntry) -> Unit)? = null

    fun configureResolver(name: String, host: String, port: Int) {
        currentResolverName = name
        upstreamHost = host
        upstreamPort = port
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                return START_NOT_STICKY
            }
        }
        startVpn()
        return START_STICKY
    }

    private fun startVpn() {
        if (runningFlag.get()) return
        try {
            startForegroundCompat()
            // DNS-only VPN: we don't route any traffic through the tunnel.
            // We only set the VPN's DNS server to 10.10.10.1. Android's
            // resolver sends DNS queries to 10.10.10.1, which arrives at
            // our tunnel via the addRoute for that single IP.
            // All other traffic (HTTPS, DoH, etc.) goes directly via the
            // underlying network — Chrome's DoH probes work normally.
            // Use a dedicated DNS server IP (10.10.10.2) that's different from
            // the VPN interface address (10.10.10.1). This ensures DNS queries
            // are routed to tun0 rather than handled locally by the kernel.
            val builder = Builder()
                .setSession("NetShield")
                .addAddress("10.10.10.1", 32)
                .addDnsServer("10.10.10.2")
                .addRoute("10.10.10.2", 32)
                .allowFamily(android.system.OsConstants.AF_INET)
                .setBlocking(true)

            // Per-app bypass can be configured via addDisallowedApplication / addAllowedApplication.
            vpnInterface = builder.establish()
                ?: run { lastError = "VPN establish returned null (permission denied?)"; stopVpn(); return }

            runningFlag.set(true)
            running = true
            lastError = null
            Log.i(TAG, "VPN established, fd=${vpnInterface?.fileDescriptor?.valid()}")
            vpnThread = Thread(this::runVpnLoop, "DnsVpnThread").apply { start() }
        } catch (e: Exception) {
            Log.e(TAG, "startVpn failed", e)
            lastError = e.message
            stopVpn()
        }
    }

    private var tunnelForwarder: com.itsash.local_dns_firewall.tunnel.TunnelForwarder? = null

    private fun runVpnLoop() {
        val pfd = vpnInterface ?: return
        val fd = pfd.fileDescriptor
        val input = FileInputStream(fd)
        val output = FileOutputStream(fd)
        val buffer = ByteArray(32767)
        val resolver: DnsResolver = UdpDnsResolver(
            currentResolverName,
            upstreamHost,
            upstreamPort,
            4000,
        ) { sock ->
            val ok = protect(sock)
            if (!ok) Log.w(TAG, "protect() FAILED for resolver socket")
            ok
        }

        // Forwarder for non-DNS traffic (TCP/UDP) to routed DNS server IPs.
        tunnelForwarder = com.itsash.local_dns_firewall.tunnel.TunnelForwarder(
            protect = { sock -> protect(sock) },
            protectTcp = { sock -> protect(sock) },
        )

        // Thread pool for async upstream resolution so the read loop never blocks.
        val pool = java.util.concurrent.Executors.newFixedThreadPool(8)
        val outputLock = Any()

        Log.i(TAG, "VPN loop started, blocking mode, async resolver")
        while (runningFlag.get()) {
            val length = try {
                input.read(buffer)
            } catch (e: Exception) {
                if (runningFlag.get()) Log.w(TAG, "read error", e)
                break
            }
            if (length <= 0) {
                continue
            }

            // Copy the packet — the buffer will be reused on the next read.
            val pktCopy = buffer.copyOf(length)
            try {
                pool.execute {
                    try {
                        handleIpPacket(pktCopy, length, output, outputLock, resolver)
                    } catch (e: Exception) {
                        Log.w(TAG, "packet handling error", e)
                    }
                }
            } catch (e: java.util.concurrent.RejectedExecutionException) {
                // Pool full — drop packet
            }
        }
        pool.shutdown()
        resolver.close()
        tunnelForwarder?.close()
        tunnelForwarder = null
        Log.i(TAG, "VPN loop ended")
    }

    private fun handleIpPacket(
        pkt: ByteArray,
        length: Int,
        out: FileOutputStream,
        outputLock: Any,
        resolver: DnsResolver,
    ) {
        if (length < 20) return
        val version = (pkt[0].toInt() ushr 4) and 0x0F
        if (version == 6) return // IPv6 — not handled yet
        if (version != 4) return
        val ihl = (pkt[0].toInt() and 0x0F) * 4
        if (length < ihl + 8) return
        val protocol = pkt[9].toInt() and 0xFF
        val srcPort = ((pkt[ihl].toInt() and 0xFF) shl 8) or (pkt[ihl + 1].toInt() and 0xFF)
        val dstPort = ((pkt[ihl + 2].toInt() and 0xFF) shl 8) or (pkt[ihl + 3].toInt() and 0xFF)

        // DNS traffic (port 53) → intercept and filter.
        // All other traffic → forward through protected socket so it doesn't break.
        if (dstPort != 53 && srcPort != 53) {
            // Non-DNS traffic to a routed IP — forward via protected socket.
            val fwd = tunnelForwarder ?: return
            val resp = when (protocol) {
                17 -> fwd.forwardUdp(pkt, length, ihl) // UDP
                6 -> fwd.forwardTcp(pkt, length, ihl)  // TCP
                else -> null
            }
            if (resp != null) {
                synchronized(outputLock) {
                    out.write(resp)
                    out.flush()
                }
            }
            return
        }

        val srcIp = ByteArray(4) { pkt[12 + it] }
        val dstIp = ByteArray(4) { pkt[16 + it] }
        val dstIpStr = "${dstIp[0].toInt() and 0xFF}.${dstIp[1].toInt() and 0xFF}.${dstIp[2].toInt() and 0xFF}.${dstIp[3].toInt() and 0xFF}"
        Log.d(TAG, "pkt: v=$version proto=$protocol $srcPort→$dstPort dst=$dstIpStr len=$length")

        if (dstPort != 53 && srcPort != 53) return

        val udpPayloadStart = ihl + 8
        val dnsLen = length - udpPayloadStart
        if (dnsLen < 12) return

        val dnsPkt = pkt.copyOfRange(udpPayloadStart, length)
        val msg = DnsPacketParser.parse(dnsPkt, dnsLen) ?: return
        val q = msg.questions.firstOrNull() ?: return
        val key = "${q.name}|${q.type}"
        queryCount.incrementAndGet()
        Log.i(TAG, "DNS query: ${q.name} type=${q.type} from=$srcPort")

        // Cache check.
        dnsCache.get(key)?.let { cached ->
            cacheHits.incrementAndGet()
            val resp = DnsPacketParser.rebuildWithId(cached, msg.header.id)
            writeIpResponse(pkt, srcIp, dstIp, srcPort, dstPort, resp, out, outputLock, swap = true)
            return
        }
        cacheMisses.incrementAndGet()

        val match = ruleEngine.evaluate(q.name)
        val action = match.action
        val response: ByteArray
        if (action == RuleAction.BLOCK) {
            response = DnsPacketParser.blockedResponse(msg)
            blockedCount.incrementAndGet()
        } else {
            val upstream = resolver.query(dnsPkt, dnsLen)
            Log.i(TAG, "upstream query for ${q.name}: ${if (upstream != null) "${upstream.size} bytes" else "FAILED"}")
            if (upstream != null) {
                response = DnsPacketParser.rebuildWithId(upstream, msg.header.id)
                allowedCount.incrementAndGet()
                // Cache for TTL (use 60s as conservative default if we can't parse TTL).
                dnsCache.put(key, upstream, 60)
            } else {
                // Upstream failure → return SERVFAIL-like response (0.0.0.0).
                response = DnsPacketParser.blockedResponse(msg)
                allowedCount.incrementAndGet()
                Log.w(TAG, "upstream FAILED for ${q.name} — returning blocked response")
            }
        }

        // Log entry — emit via the static bridge to the activity's EventChannel.
        VpnLogBridge.logSink?.invoke(
            QueryLogEntry(
                timestamp = System.currentTimeMillis(),
                domain = q.name,
                queryType = q.type,
                sourceApp = null, // per-app attribution requires uid→pkg mapping; not reliable here.
                action = action.name,
                category = match.category?.name,
                source = match.source.name,
                matchedRule = match.matchedRule,
            )
        )

        writeIpResponse(pkt, srcIp, dstIp, srcPort, dstPort, response, out, outputLock, swap = true)
    }

    /** Write an IP/UDP response back into the VPN tunnel. */
    private fun writeIpResponse(
        originalPkt: ByteArray,
        origSrcIp: ByteArray,
        origDstIp: ByteArray,
        origSrcPort: Int,
        origDstPort: Int,
        dnsResponse: ByteArray,
        out: FileOutputStream,
        outputLock: Any,
        swap: Boolean,
    ) {
        try {
            // Build IPv4 + UDP header then payload.
            val totalLen = 20 + 8 + dnsResponse.size
            val ip = ByteArray(20)
            ip[0] = 0x45.toByte() // version 4, IHL 5
            ip[1] = 0
            ip[2] = ((totalLen ushr 8) and 0xFF).toByte()
            ip[3] = (totalLen and 0xFF).toByte()
            // identification, flags, frag — leave 0
            ip[8] = 64 // TTL
            ip[9] = 17 // UDP
            // swap src/dst
            System.arraycopy(origDstIp, 0, ip, 12, 4)
            System.arraycopy(origSrcIp, 0, ip, 16, 4)
            // checksum
            var sum = 0
            for (i in 0 until 20 step 2) {
                sum += ((ip[i].toInt() and 0xFF) shl 8) or (ip[i + 1].toInt() and 0xFF)
            }
            while (sum ushr 16 != 0) sum = (sum and 0xFFFF) + (sum ushr 16)
            sum = sum.inv() and 0xFFFF
            ip[10] = ((sum ushr 8) and 0xFF).toByte()
            ip[11] = (sum and 0xFF).toByte()

            val udp = ByteArray(8)
            udp[0] = ((origDstPort ushr 8) and 0xFF).toByte()
            udp[1] = (origDstPort and 0xFF).toByte()
            udp[2] = ((origSrcPort ushr 8) and 0xFF).toByte()
            udp[3] = (origSrcPort and 0xFF).toByte()
            val udpLen = 8 + dnsResponse.size
            udp[4] = ((udpLen ushr 8) and 0xFF).toByte()
            udp[5] = (udpLen and 0xFF).toByte()
            // UDP checksum optional in IPv4 → 0

            // Write the complete IP packet in a single write — the VPN tunnel
            // expects one complete IP datagram per write, not fragmented writes.
            val packet = ByteArray(totalLen)
            System.arraycopy(ip, 0, packet, 0, 20)
            System.arraycopy(udp, 0, packet, 20, 8)
            System.arraycopy(dnsResponse, 0, packet, 28, dnsResponse.size)
            synchronized(outputLock) {
                out.write(packet)
                out.flush()
            }
        } catch (e: Exception) {
            Log.w(TAG, "writeIpResponse failed", e)
        }
    }

    /** Get the system's active DNS server IPs so we can route them through the tunnel. */
    private fun getSystemDnsServers(): List<String> {
        val servers = mutableSetOf<String>()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
                val active = cm.activeNetwork
                if (active != null) {
                    val linkProps = cm.getLinkProperties(active)
                    if (linkProps != null) {
                        for (addr in linkProps.dnsServers) {
                            servers.add(addr.hostAddress ?: continue)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "getSystemDnsServers failed", e)
        }
        // Fallback: common emulator DNS
        if (servers.isEmpty()) {
            servers.add("10.0.2.3")
            servers.add("10.0.2.4")
        }
        // Do NOT add public DNS servers (8.8.8.8, 1.1.1.1) — Chrome's DoH
        // (TCP 443) to those IPs must go direct via the underlying network.
        return servers.filter { it.contains('.') } // IPv4 only for now
    }

    private fun stopVpn() {
        runningFlag.set(false)
        running = false
        try { vpnThread?.interrupt() } catch (_: Exception) {}
        vpnThread = null
        try { vpnInterface?.close() } catch (_: Exception) {}
        vpnInterface = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onRevoke() {
        // VPN permission revoked by user or always-on reset.
        stopVpn()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    // Handle system network changes — VpnService restart is recommended.
    override fun onLowMemory() {
        dnsCache.clear()
        super.onLowMemory()
    }

    private fun startForegroundCompat() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "DNS Firewall", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val notif = buildNotification(blockedCount.get())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } catch (e: SecurityException) {
                // Fallback if FOREGROUND_SERVICE_SPECIAL_USE permission isn't granted at runtime.
                try {
                    startForeground(NOTIF_ID, notif)
                } catch (e2: Exception) {
                    Log.e(TAG, "startForeground fallback failed", e2)
                }
            }
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun buildNotification(blockedToday: Long): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return androidx.core.app.NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("NetShield")
            .setContentText("Protection active · $blockedToday domains blocked today")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(pi)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    fun updateNotification(blockedToday: Long) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID, buildNotification(blockedToday))
        } catch (_: Exception) {}
    }

    data class QueryLogEntry(
        val timestamp: Long,
        val domain: String,
        val queryType: Int,
        val sourceApp: String?,
        val action: String,
        val category: String?,
        val source: String,
        val matchedRule: String,
    )
}