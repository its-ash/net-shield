package com.itsash.local_dns_firewall.dns

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Forwards DNS queries to a configured upstream resolver over UDP/TCP.
 * Extensible: DoH/DoT implementations can be added behind [DnsResolver].
 *
 * [protectSocket] is called on each socket so that the VpnService can
 * exclude the upstream connection from the VPN tunnel — otherwise the
 * resolver's own DNS traffic loops back through the VPN.
 */
interface DnsResolver {
    val name: String
    fun query(packet: ByteArray, length: Int): ByteArray?
    fun close()
}

class UdpDnsResolver(
    override val name: String,
    private val host: String,
    private val port: Int = 53,
    private val timeoutMs: Int = 4000,
    private val protectSocket: ((java.net.DatagramSocket) -> Boolean)? = null,
) : DnsResolver {

    @Volatile private var address: InetAddress? = null

    private fun resolveAddress(): InetAddress? {
        address?.let { return it }
        return try {
            val a = InetAddress.getByName(host)
            address = a
            a
        } catch (e: Exception) { null }
    }

    override fun query(packet: ByteArray, length: Int): ByteArray? {
        val addr = resolveAddress() ?: return null
        return try {
            DatagramSocket().use { sock ->
                protectSocket?.invoke(sock)
                sock.soTimeout = timeoutMs
                sock.send(DatagramPacket(packet, length, addr, port))
                val buf = ByteArray(4096)
                val resp = DatagramPacket(buf, buf.size)
                sock.receive(resp)
                resp.data.copyOf(resp.length)
            }
        } catch (e: Exception) { null }
    }

    override fun close() {}
}

class TcpDnsResolver(
    override val name: String,
    private val host: String,
    private val port: Int = 53,
    private val timeoutMs: Int = 5000,
    private val protectSocket: ((java.net.Socket) -> Boolean)? = null,
) : DnsResolver {

    override fun query(packet: ByteArray, length: Int): ByteArray? {
        return try {
            Socket().use { sock ->
                protectSocket?.invoke(sock)
                sock.soTimeout = timeoutMs
                sock.connect(InetSocketAddress(host, port), timeoutMs)
                sock.getOutputStream().use { out ->
                    out.write((length ushr 8) and 0xFF)
                    out.write(length and 0xFF)
                    out.write(packet, 0, length)
                    out.flush()
                }
                val input = sock.getInputStream()
                val lenHi = input.read()
                val lenLo = input.read()
                if (lenHi < 0 || lenLo < 0) return null
                val respLen = (lenHi shl 8) or lenLo
                val resp = ByteArray(respLen)
                var read = 0
                while (read < respLen) {
                    val n = input.read(resp, read, respLen - read)
                    if (n < 0) break
                    read += n
                }
                if (read == respLen) resp else null
            }
        } catch (e: Exception) { null }
    }

    override fun close() {}
}