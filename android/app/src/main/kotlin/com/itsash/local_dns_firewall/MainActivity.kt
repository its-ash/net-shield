package com.itsash.local_dns_firewall

import android.content.Intent
import android.net.VpnService
import com.itsash.local_dns_firewall.dns.DnsPacketParser
import com.itsash.local_dns_firewall.dns.UdpDnsResolver
import com.itsash.local_dns_firewall.rules.RuleAction
import com.itsash.local_dns_firewall.rules.RuleCategory
import com.itsash.local_dns_firewall.rules.RuleEntry
import com.itsash.local_dns_firewall.rules.RuleSource
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentLinkedQueue

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.itsash.local_dns_firewall/vpn"
    private val LOG_EVENT = "com.itsash.local_dns_firewall/logs"
    private val REQUEST_VPN = 100
    private val REQUEST_VPN_WIDGET = 101

    private var pendingStart: MethodChannel.Result? = null
    private var logSink: EventChannel.EventSink? = null
    private val logBuffer = ConcurrentLinkedQueue<Map<String, Any?>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        VpnLogBridge.logSink = { entry ->
            val map: Map<String, Any?> = mapOf(
                "timestamp" to entry.timestamp,
                "domain" to entry.domain,
                "queryType" to entry.queryType,
                "sourceApp" to entry.sourceApp,
                "action" to entry.action,
                "category" to entry.category,
                "source" to entry.source,
                "matchedRule" to entry.matchedRule,
            )
            logBuffer.add(map)
            while (logBuffer.size > 500) logBuffer.poll()
            runOnUiThread { logSink?.success(map) }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LOG_EVENT).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    logSink = sink
                    logBuffer.toList().forEach { sink?.success(it) }
                }
                override fun onCancel(args: Any?) { logSink = null }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            android.util.Log.i("NetShield", "method channel: ${call.method}")
            when (call.method) {
                "prepareVpn" -> {
                    val prep = VpnService.prepare(this)
                    if (prep != null) {
                        pendingStart = result
                        @Suppress("DEPRECATION")
                        startActivityForResult(prep, REQUEST_VPN)
                    } else {
                        result.success(true)
                    }
                }
                "startVpn" -> {
                    val resolverName = call.argument<String>("resolverName") ?: "System default"
                    val host = call.argument<String>("host") ?: "1.1.1.1"
                    val port = call.argument<Int>("port") ?: 53
                    DnsVpnService.currentResolverName = resolverName
                    DnsVpnService.upstreamHost = host
                    DnsVpnService.upstreamPort = port
                    val intent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_START
                    }
                    startService(intent)
                    result.success(true)
                }
                "stopVpn" -> {
                    val intent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "isRunning" -> result.success(DnsVpnService.running)
                "getStats" -> {
                    result.success(mapOf(
                        "total" to DnsVpnService.queryCount.get(),
                        "blocked" to DnsVpnService.blockedCount.get(),
                        "allowed" to DnsVpnService.allowedCount.get(),
                        "cacheHits" to DnsVpnService.cacheHits.get(),
                        "cacheMisses" to DnsVpnService.cacheMisses.get(),
                        "cacheSize" to DnsVpnService.dnsCache.size(),
                        "ruleCount" to DnsVpnService.ruleEngine.size(),
                        "resolver" to DnsVpnService.currentResolverName,
                        "lastError" to (DnsVpnService.lastError ?: ""),
                    ))
                }
                "syncRules" -> {
                    @Suppress("UNCHECKED_CAST")
                    val allowlist = (call.argument<List<*>>("allowlist") ?: emptyList<Any>())
                        .map { it as Map<String, Any> }
                    @Suppress("UNCHECKED_CAST")
                    val blocklist = (call.argument<List<*>>("blocklist") ?: emptyList<Any>())
                        .map { it as Map<String, Any> }
                    val allowEntries = allowlist.map { mapToEntry(it, RuleAction.ALLOW, RuleCategory.ALLOWLIST, RuleSource.USER_ALLOWLIST) }
                    val blockEntries = blocklist.map { mapToEntry(it, RuleAction.BLOCK, RuleCategory.CUSTOM, RuleSource.USER_BLOCKLIST) }
                    DnsVpnService.ruleEngine.rebuild(allowEntries, blockEntries)
                    result.success(true)
                }
                "clearCache" -> { DnsVpnService.dnsCache.clear(); result.success(true) }
                "testDomain" -> {
                    val domain = call.argument<String>("domain") ?: ""
                    val host = call.argument<String>("host") ?: "1.1.1.1"
                    val port = call.argument<Int>("port") ?: 53
                    result.success(testDomain(domain, host, port))
                }
                "testRule" -> {
                    val domain = call.argument<String>("domain") ?: ""
                    val m = DnsVpnService.ruleEngine.evaluate(domain)
                    result.success(mapOf(
                        "action" to m.action.name,
                        "category" to (m.category?.name ?: ""),
                        "source" to m.source.name,
                        "matchedRule" to m.matchedRule,
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun mapToEntry(
        m: Map<String, Any>,
        action: RuleAction,
        category: RuleCategory,
        source: RuleSource,
    ): RuleEntry {
        val domain = (m["domain"] as? String ?: "").lowercase().trim()
        val exact = m["exact"] as? Boolean ?: false
        val catStr = m["category"] as? String
        val cat = when (catStr?.uppercase()) {
            "ADS" -> RuleCategory.ADS
            "TRACKERS" -> RuleCategory.TRACKERS
            "MALWARE" -> RuleCategory.MALWARE
            "TELEMETRY" -> RuleCategory.TELEMETRY
            "CUSTOM" -> RuleCategory.CUSTOM
            "ALLOWLIST" -> RuleCategory.ALLOWLIST
            else -> category
        }
        return RuleEntry(domain, action, cat, source, exact)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_VPN -> {
                pendingStart?.success(resultCode == RESULT_OK)
                pendingStart = null
            }
            REQUEST_VPN_WIDGET -> {
                if (resultCode == RESULT_OK) {
                    startService(Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_START
                    })
                }
                widgetStartPending = false
                com.itsash.local_dns_firewall.widget.NetShieldWidgetProvider.updateAllWidgets(applicationContext)
            }
        }
    }

    private fun testDomain(domain: String, host: String, port: Int): Map<String, Any?> {
        val match = DnsVpnService.ruleEngine.evaluate(domain)
        if (match.action == RuleAction.BLOCK) {
            return mapOf(
                "blocked" to true,
                "action" to "BLOCK",
                "category" to (match.category?.name ?: ""),
                "source" to match.source.name,
                "matchedRule" to match.matchedRule,
                "ips" to emptyList<String>(),
                "responseTimeMs" to 0,
                "cacheHit" to false,
            )
        }
        val start = System.currentTimeMillis()
        val query = buildDnsQuery(domain)
        val resolver = UdpDnsResolver("test", host, port, 4000)
        val resp = resolver.query(query, query.size)
        val elapsed = System.currentTimeMillis() - start
        val ips = parseAnswerIps(resp)
        return mapOf(
            "blocked" to false,
            "action" to "ALLOW",
            "category" to "",
            "source" to match.source.name,
            "matchedRule" to match.matchedRule,
            "ips" to ips,
            "responseTimeMs" to elapsed,
            "cacheHit" to false,
        )
    }

    private fun buildDnsQuery(domain: String): ByteArray {
        val out = java.io.ByteArrayOutputStream(64)
        out.write(0); out.write(1)
        out.write(0x01); out.write(0x00)
        out.write(0); out.write(1)
        out.write(0); out.write(0)
        out.write(0); out.write(0)
        out.write(0); out.write(0)
        for (label in domain.split(".")) {
            val b = label.toByteArray(Charsets.US_ASCII)
            out.write(b.size)
            out.write(b)
        }
        out.write(0)
        out.write(0); out.write(1)
        out.write(0); out.write(1)
        return out.toByteArray()
    }

    private fun parseAnswerIps(resp: ByteArray?): List<String> {
        if (resp == null || resp.size < 12) return emptyList()
        val msg = DnsPacketParser.parse(resp, resp.size) ?: return emptyList()
        val buf = java.nio.ByteBuffer.wrap(resp, 0, resp.size).order(java.nio.ByteOrder.BIG_ENDIAN)
        buf.position(12)
        for (i in 0 until msg.header.qdCount) {
            skipName(buf, resp)
            buf.position(buf.position() + 4)
        }
        val ips = ArrayList<String>()
        for (i in 0 until msg.header.anCount) {
            skipName(buf, resp)
            val type = buf.short.toInt() and 0xFFFF
            buf.short
            buf.int
            val rdLen = buf.short.toInt() and 0xFFFF
            val rdStart = buf.position()
            if (type == 1 && rdLen == 4) {
                ips.add("${resp[rdStart].toInt() and 0xFF}.${resp[rdStart+1].toInt() and 0xFF}.${resp[rdStart+2].toInt() and 0xFF}.${resp[rdStart+3].toInt() and 0xFF}")
            }
            buf.position(rdStart + rdLen)
        }
        return ips
    }

    private fun skipName(buf: java.nio.ByteBuffer, src: ByteArray) {
        while (true) {
            val b = src[buf.position()].toInt() and 0xFF
            if (b == 0) { buf.position(buf.position() + 1); return }
            if ((b and 0xC0) == 0xC0) { buf.position(buf.position() + 2); return }
            buf.position(buf.position() + 1 + (b and 0x3F))
        }
    }

    // ── Home-screen widget integration ──────────────────────────────────
    // When the widget is tapped and VPN permission hasn't been granted yet,
    // the widget launches MainActivity with this extra. We trigger the normal
    // prepare → start flow so the user sees the Android VPN consent dialog.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWidgetStart(intent)
    }

    override fun onResume() {
        super.onResume()
        handleWidgetStart(intent)
        // Refresh widget visuals whenever the app comes to the foreground.
        com.itsash.local_dns_firewall.widget.NetShieldWidgetProvider.updateAllWidgets(applicationContext)
    }

    private var widgetStartPending = false

    private fun handleWidgetStart(intent: Intent?) {
        if (intent?.getBooleanExtra("widget_start_vpn", false) == true && !widgetStartPending) {
            widgetStartPending = true
            intent.removeExtra("widget_start_vpn")
            if (DnsVpnService.running) {
                widgetStartPending = false
                return
            }
            val prep = VpnService.prepare(this)
            if (prep != null) {
                @Suppress("DEPRECATION")
                startActivityForResult(prep, REQUEST_VPN_WIDGET)
            } else {
                startService(Intent(this, DnsVpnService::class.java).apply {
                    action = DnsVpnService.ACTION_START
                })
                widgetStartPending = false
            }
        }
    }
}

object VpnLogBridge {
    @Volatile var logSink: ((DnsVpnService.QueryLogEntry) -> Unit)? = null
}
