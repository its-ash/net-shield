package com.itsash.local_dns_firewall.tunnel

import android.util.Log
import java.net.InetAddress
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import java.nio.channels.SocketChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * Forwards non-DNS IP packets through protected sockets back to the real network.
 * This is needed because we route 0.0.0.0/0 through the VPN tunnel — we must
 * relay all traffic that isn't DNS (port 53) to the underlying network.
 */
class TunnelForwarder(private val protect: (java.net.DatagramSocket) -> Boolean,
                      private val protectTcp: (java.net.Socket) -> Boolean) {

    companion object { private const val TAG = "TunnelForwarder" }

    // UDP sessions keyed by srcPort+dstPort+dstIp
    private val udpSessions = ConcurrentHashMap<String, DatagramChannel>()

    // TCP sessions keyed by srcPort+dstPort+dstIp
    private val tcpSessions = ConcurrentHashMap<String, SocketChannel>()

    /**
     * Forward a UDP packet (non-DNS) to its destination via a protected socket.
     * Returns a response packet (IP+UDP+payload) if one arrives, or null.
     */
    fun forwardUdp(pkt: ByteArray, length: Int, ihl: Int): ByteArray? {
        val srcIp = ByteArray(4) { pkt[12 + it] }
        val dstIp = ByteArray(4) { pkt[16 + it] }
        val srcPort = ((pkt[ihl].toInt() and 0xFF) shl 8) or (pkt[ihl + 1].toInt() and 0xFF)
        val dstPort = ((pkt[ihl + 2].toInt() and 0xFF) shl 8) or (pkt[ihl + 3].toInt() and 0xFF)
        val dstAddr = InetAddress.getByAddress(dstIp)
        val key = "$srcPort:$dstPort:${dstAddr.hostAddress}"
        val payloadStart = ihl + 8
        val payloadLen = length - payloadStart
        val payload = pkt.copyOfRange(payloadStart, length)

        try {
            var channel = udpSessions[key]
            if (channel == null || !channel.isOpen) {
                channel = DatagramChannel.open()
                protect(channel.socket())
                channel.configureBlocking(true)
                channel.socket().soTimeout = 30000
                udpSessions[key] = channel
            }

            channel.send(ByteBuffer.wrap(payload), InetSocketAddress(dstAddr, dstPort))

            // Try to receive a response (blocking with timeout)
            val respBuf = ByteBuffer.allocate(32767)
            val src = channel.receive(respBuf) ?: return null
            respBuf.flip()
            val respPayload = ByteArray(respBuf.remaining())
            respBuf.get(respPayload)

            // Build response IP+UDP packet
            return buildUdpPacket(dstIp, srcIp, dstPort, srcPort, respPayload)
        } catch (e: Exception) {
            Log.w(TAG, "UDP forward error: ${e.message}")
            udpSessions.remove(key)
            return null
        }
    }

    /**
     * Forward a TCP packet (non-DNS) to its destination via a protected socket.
     * For simplicity, this handles SYN → connect, data → write/read, FIN → close.
     */
    fun forwardTcp(pkt: ByteArray, length: Int, ihl: Int): ByteArray? {
        val dstIp = ByteArray(4) { pkt[16 + it] }
        val srcPort = ((pkt[ihl].toInt() and 0xFF) shl 8) or (pkt[ihl + 1].toInt() and 0xFF)
        val dstPort = ((pkt[ihl + 2].toInt() and 0xFF) shl 8) or (pkt[ihl + 3].toInt() and 0xFF)
        val dstAddr = InetAddress.getByAddress(dstIp)
        val key = "$srcPort:$dstPort:${dstAddr.hostAddress}"
        val flags = pkt[ihl + 10].toInt() and 0xFF // TCP flags
        val FIN = 0x01
        val RST = 0x04
        val SYN = 0x02

        try {
            if ((flags and SYN) != 0) {
                // New connection
                val channel = SocketChannel.open()
                protectTcp(channel.socket())
                channel.configureBlocking(true)
                channel.socket().soTimeout = 30000
                channel.connect(InetSocketAddress(dstAddr, dstPort))
                tcpSessions[key] = channel
                // Return a SYN-ACK (simplified — let the kernel handle the rest)
                return null
            }

            if ((flags and (FIN or RST)) != 0) {
                tcpSessions.remove(key)?.close()
                return null
            }

            val channel = tcpSessions[key] ?: return null
            val payloadStart = ihl + ((pkt[ihl + 12].toInt() ushr 4) and 0x0F) * 4 // TCP header length
            if (payloadStart >= length) return null // ACK with no data
            val payload = pkt.copyOfRange(payloadStart, length)
            channel.write(ByteBuffer.wrap(payload))

            // Read response
            val respBuf = ByteBuffer.allocate(32767)
            val n = channel.read(respBuf)
            if (n <= 0) return null
            respBuf.flip()
            val respPayload = ByteArray(respBuf.remaining())
            respBuf.get(respPayload)
            return buildTcpPacket(dstIp, ByteArray(4) { pkt[12 + it] }, dstPort, srcPort, respPayload)
        } catch (e: Exception) {
            Log.w(TAG, "TCP forward error: ${e.message}")
            tcpSessions.remove(key)
            return null
        }
    }

    private fun buildUdpPacket(srcIp: ByteArray, dstIp: ByteArray, srcPort: Int, dstPort: Int, payload: ByteArray): ByteArray {
        val totalLen = 20 + 8 + payload.size
        val pkt = ByteArray(totalLen)
        // IP header
        pkt[0] = 0x45.toByte()
        pkt[2] = ((totalLen ushr 8) and 0xFF).toByte()
        pkt[3] = (totalLen and 0xFF).toByte()
        pkt[8] = 64 // TTL
        pkt[9] = 17 // UDP
        System.arraycopy(srcIp, 0, pkt, 12, 4)
        System.arraycopy(dstIp, 0, pkt, 16, 4)
        // IP checksum
        var sum = 0
        for (i in 0 until 20 step 2) {
            sum += ((pkt[i].toInt() and 0xFF) shl 8) or (pkt[i + 1].toInt() and 0xFF)
        }
        while (sum ushr 16 != 0) sum = (sum and 0xFFFF) + (sum ushr 16)
        sum = sum.inv() and 0xFFFF
        pkt[10] = ((sum ushr 8) and 0xFF).toByte()
        pkt[11] = (sum and 0xFF).toByte()
        // UDP header
        pkt[20] = ((srcPort ushr 8) and 0xFF).toByte()
        pkt[21] = (srcPort and 0xFF).toByte()
        pkt[22] = ((dstPort ushr 8) and 0xFF).toByte()
        pkt[23] = (dstPort and 0xFF).toByte()
        val udpLen = 8 + payload.size
        pkt[24] = ((udpLen ushr 8) and 0xFF).toByte()
        pkt[25] = (udpLen and 0xFF).toByte()
        // Payload
        System.arraycopy(payload, 0, pkt, 28, payload.size)
        return pkt
    }

    private fun buildTcpPacket(srcIp: ByteArray, dstIp: ByteArray, srcPort: Int, dstPort: Int, payload: ByteArray): ByteArray {
        val tcpHdrLen = 20
        val totalLen = 20 + tcpHdrLen + payload.size
        val pkt = ByteArray(totalLen)
        pkt[0] = 0x45.toByte()
        pkt[2] = ((totalLen ushr 8) and 0xFF).toByte()
        pkt[3] = (totalLen and 0xFF).toByte()
        pkt[8] = 64
        pkt[9] = 6 // TCP
        System.arraycopy(srcIp, 0, pkt, 12, 4)
        System.arraycopy(dstIp, 0, pkt, 16, 4)
        var sum = 0
        for (i in 0 until 20 step 2) {
            sum += ((pkt[i].toInt() and 0xFF) shl 8) or (pkt[i + 1].toInt() and 0xFF)
        }
        while (sum ushr 16 != 0) sum = (sum and 0xFFFF) + (sum ushr 16)
        sum = sum.inv() and 0xFFFF
        pkt[10] = ((sum ushr 8) and 0xFF).toByte()
        pkt[11] = (sum and 0xFF).toByte()
        // TCP header (minimal — ACK + PSH, seq/ack left as 0)
        pkt[20] = ((srcPort ushr 8) and 0xFF).toByte()
        pkt[21] = (srcPort and 0xFF).toByte()
        pkt[22] = ((dstPort ushr 8) and 0xFF).toByte()
        pkt[23] = (dstPort and 0xFF).toByte()
        pkt[32] = 0x50.toByte() // data offset = 5 (20 bytes)
        pkt[33] = 0x18.toByte() // ACK + PSH
        pkt[34] = 0xFF.toByte() // window
        pkt[35] = 0xFF.toByte()
        System.arraycopy(payload, 0, pkt, 40, payload.size)
        return pkt
    }

    fun close() {
        udpSessions.values.forEach { try { it.close() } catch (_: Exception) {} }
        tcpSessions.values.forEach { try { it.close() } catch (_: Exception) {} }
        udpSessions.clear()
        tcpSessions.clear()
    }
}