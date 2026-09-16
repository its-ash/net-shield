package com.itsash.local_dns_firewall.dns

import java.util.concurrent.ConcurrentHashMap

/**
 * In-memory DNS cache that respects TTL. Keyed by "name|type".
 * Thread-safe, bounded by [maxEntries] (LRU-ish via insertion order eviction).
 */
class DnsCache(private val maxEntries: Int = 4096) {

    private data class Entry(val data: ByteArray, val expiresAt: Long)
    private val store = ConcurrentHashMap<String, Entry>()
    private val order = LinkedHashSet<String>()
    private val lock = Any()

    fun get(key: String): ByteArray? {
        val e = store[key] ?: return null
        if (System.currentTimeMillis() > e.expiresAt) {
            store.remove(key)
            synchronized(lock) { order.remove(key) }
            return null
        }
        // Refresh LRU position.
        synchronized(lock) {
            order.remove(key)
            order.add(key)
        }
        return e.data
    }

    fun put(key: String, data: ByteArray, ttlSeconds: Long) {
        if (ttlSeconds <= 0) return
        synchronized(lock) {
            while (order.size >= maxEntries) {
                val it = order.iterator()
                if (it.hasNext()) {
                    val oldest = it.next()
                    it.remove()
                    store.remove(oldest)
                } else break
            }
            order.add(key)
        }
        store[key] = Entry(data, System.currentTimeMillis() + ttlSeconds * 1000)
    }

    fun clear() {
        store.clear()
        synchronized(lock) { order.clear() }
    }

    fun size(): Int = store.size
}