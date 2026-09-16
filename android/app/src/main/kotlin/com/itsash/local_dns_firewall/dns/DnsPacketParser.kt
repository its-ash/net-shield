package com.itsash.local_dns_firewall.dns

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Minimal DNS message parser/writer for UDP and TCP.
 * Only the bits required for a local filtering resolver: header, question section,
 * and synthesised A/AAAA "blocked" / NXDOMAIN responses. No EDNS, no recursion.
 */
object DnsPacketParser {

    const val TYPE_A: Int = 1
    const val TYPE_AAAA: Int = 28
    const val TYPE_CNAME: Int = 5
    const val TYPE_PTR: Int = 12
    const val TYPE_MX: Int = 15
    const val TYPE_TXT: Int = 16
    const val TYPE_SRV: Int = 33
    const val TYPE_HTTPS: Int = 65
    const val CLASS_IN: Int = 1

    data class Question(val name: String, val type: Int, val klass: Int)
    data class Header(
        val id: Int,
        val flags: Int,
        val qdCount: Int,
        val anCount: Int,
        val nsCount: Int,
        val arCount: Int,
    )

    data class Message(
        val header: Header,
        val questions: List<Question>,
        val raw: ByteArray,
    )

    fun parse(packet: ByteArray, length: Int): Message? = try {
        if (length < 12) return null
        val buf = ByteBuffer.wrap(packet, 0, length).order(ByteOrder.BIG_ENDIAN)
        val id = buf.short.toInt() and 0xFFFF
        val flags = buf.short.toInt() and 0xFFFF
        val qd = buf.short.toInt() and 0xFFFF
        val an = buf.short.toInt() and 0xFFFF
        val ns = buf.short.toInt() and 0xFFFF
        val ar = buf.short.toInt() and 0xFFFF
        val questions = ArrayList<Question>(qd.coerceAtMost(8))
        repeat(qd) {
            val name = readName(buf, packet, length) ?: return null
            val type = buf.short.toInt() and 0xFFFF
            val klass = buf.short.toInt() and 0xFFFF
            questions.add(Question(name.lowercase(), type, klass))
        }
        Message(Header(id, flags, qd, an, ns, ar), questions, packet.copyOf(length))
    } catch (e: Exception) {
        null
    }

    /** RFC1035 label decoding with compression pointers. */
    private fun readName(buf: ByteBuffer, src: ByteArray, len: Int): String? {
        val labels = ArrayList<String>(8)
        var pos = buf.position()
        var jumped = false
        var jumps = 0
        var saved = -1
        while (true) {
            if (pos >= len) return null
            val b = src[pos].toInt() and 0xFF
            if (b == 0) {
                pos++
                if (!jumped) buf.position(pos) else if (saved >= 0) buf.position(saved)
                return labels.joinToString(".")
            }
            when {
                (b and 0xC0) == 0xC0 -> {
                    if (pos + 1 >= len) return null
                    val ptr = ((b and 0x3F) shl 8) or (src[pos + 1].toInt() and 0xFF)
                    if (!jumped) saved = pos + 2
                    pos = ptr
                    jumped = true
                    if (++jumps > 16) return null
                }
                (b and 0xC0) == 0 -> {
                    val labelLen = b and 0x3F
                    pos++
                    if (pos + labelLen > len) return null
                    labels.add(String(src, pos, labelLen, Charsets.US_ASCII))
                    pos += labelLen
                }
                else -> return null
            }
        }
    }

    /** Build a "blocked" response: A/AAAA → 0.0.0.0 / ::, others → NXDOMAIN. */
    fun blockedResponse(query: Message): ByteArray {
        val q = query.questions.firstOrNull() ?: return emptyArray<Byte>().toByteArray()
        val out = ByteArrayOutputStream(64)
        val id = query.header.id
        // QR=1, AA=0, TC=0, RD copied, RA=1, rcode=0 (NOERROR) for A/AAAA, 3 (NXDOMAIN) otherwise
        val rd = query.header.flags and 0x0100
        val rcode = if (q.type == TYPE_A || q.type == TYPE_AAAA) 0 else 3
        val flags = 0x8000 or rd or 0x0080 or rcode
        writeU16(out, id)
        writeU16(out, flags)
        writeU16(out, query.questions.size)
        writeU16(out, if (rcode == 0) 1 else 0)
        writeU16(out, 0)
        writeU16(out, 0)
        for (question in query.questions) {
            writeName(out, question.name)
            writeU16(out, question.type)
            writeU16(out, question.klass)
        }
        if (rcode == 0) {
            // Answer: A → 0.0.0.0, AAAA → ::
            writeName(out, q.name)
            writeU16(out, q.type)
            writeU16(out, CLASS_IN)
            writeU32(out, 60) // TTL 60s
            when (q.type) {
                TYPE_A -> {
                    writeU16(out, 4)
                    out.write(0); out.write(0); out.write(0); out.write(0)
                }
                TYPE_AAAA -> {
                    writeU16(out, 16)
                    repeat(16) { out.write(0) }
                }
                else -> {
                    writeU16(out, 0)
                }
            }
        }
        return out.toByteArray()
    }

    /** Rebuild a forwarded upstream response with the original query id. */
    fun rebuildWithId(upstream: ByteArray, originalId: Int): ByteArray {
        if (upstream.size < 2) return upstream
        val copy = upstream.copyOf()
        copy[0] = ((originalId ushr 8) and 0xFF).toByte()
        copy[1] = (originalId and 0xFF).toByte()
        return copy
    }

    private fun writeName(out: ByteArrayOutputStream, name: String) {
        if (name.isNotEmpty()) {
            for (label in name.split(".")) {
                val bytes = label.toByteArray(Charsets.US_ASCII)
                if (bytes.size > 63) throw IllegalArgumentException("label too long")
                out.write(bytes.size)
                out.write(bytes)
            }
        }
        out.write(0)
    }

    private fun writeU16(out: ByteArrayOutputStream, v: Int) {
        out.write((v ushr 8) and 0xFF)
        out.write(v and 0xFF)
    }

    private fun writeU32(out: ByteArrayOutputStream, v: Int) {
        out.write((v ushr 24) and 0xFF)
        out.write((v ushr 16) and 0xFF)
        out.write((v ushr 8) and 0xFF)
        out.write(v and 0xFF)
    }
}