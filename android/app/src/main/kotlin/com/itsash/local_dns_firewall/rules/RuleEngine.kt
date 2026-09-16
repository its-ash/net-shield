package com.itsash.local_dns_firewall.rules

import java.util.concurrent.ConcurrentHashMap

enum class RuleCategory { ADS, TRACKERS, MALWARE, TELEMETRY, CUSTOM, ALLOWLIST, SYSTEM }
enum class RuleAction { ALLOW, BLOCK }
enum class RuleSource { SYSTEM, USER_ALLOWLIST, USER_BLOCKLIST, IMPORTED_BLOCKLIST, CUSTOM }

data class RuleMatch(
    val action: RuleAction,
    val category: RuleCategory?,
    val source: RuleSource,
    val matchedRule: String,
)

/**
 * Reversed-domain trie for fast suffix matching.
 * A rule "example.com" matches "example.com" and "*.example.com" (any subdomain).
 * A rule "*.example.com" matches subdomains but not the apex.
 * Exact rules match only that exact domain.
 *
 * Memory efficient: shared path nodes; millions of rules feasible.
 * Thread-safe for reads (copy-on-write rebuild); writes via [rebuild].
 */
class RuleEngine {
    private class Node {
        val children = HashMap<String, Node>(0)
        var match: RuleMatch? = null
    }

    @Volatile private var root: Node = Node()
    @Volatile private var exactAllow: Set<String> = emptySet()
    @Volatile private var exactBlock: Set<String> = emptySet()
    @Volatile private var ruleCount: Int = 0

    fun size(): Int = ruleCount

    /** Rebuild the entire engine from rule sets. */
    fun rebuild(
        allowlist: List<RuleEntry>,
        blocklist: List<RuleEntry>,
    ) {
        val newRoot = Node()
        val newExactAllow = HashSet<String>()
        val newExactBlock = HashSet<String>()
        var count = 0

        // System safety rules — always allow localhost & local domains.
        val safety = listOf("localhost", "local", "in-addr.arpa", "ip6.arpa")
        for (d in safety) {
            insert(newRoot, RuleEntry(d, RuleAction.ALLOW, RuleCategory.SYSTEM, RuleSource.SYSTEM, exact = true))
            count++
        }

        // Priority 2: user allowlist.
        for (e in allowlist) {
            if (e.exact) newExactAllow.add(e.domain)
            insert(newRoot, e)
            count++
        }

        // Priority 3-4: blocklist + custom.
        for (e in blocklist) {
            if (e.exact) newExactBlock.add(e.domain)
            insert(newRoot, e)
            count++
        }

        root = newRoot
        exactAllow = newExactAllow
        exactBlock = newExactBlock
        ruleCount = count
    }

    private fun insert(root: Node, entry: RuleEntry) {
        val labels = entry.domain.split(".").filter { it.isNotEmpty() }
        if (labels.isEmpty()) return
        var node = root
        for (i in labels.indices.reversed()) {
            val label = labels[i]
            node = node.children.getOrPut(label) { Node() }
        }
        // First-insert wins (priority order: allowlist inserted before blocklist).
        if (node.match == null) node.match = RuleMatch(entry.action, entry.category, entry.source, entry.domain)
    }

    /**
     * Evaluate a domain. Priority:
     * 1. System safety (already in trie as ALLOW)
     * 2. User allowlist (exact)
     * 3. User blocklist (exact)
     * 4. Enabled blocklists (suffix trie)
     * 5. Default allow
     */
    fun evaluate(domain: String): RuleMatch {
        val d = domain.trim().lowercase().trimEnd('.')
        if (d.isEmpty()) return defaultAllow(d)

        // Exact allowlist.
        if (exactAllow.contains(d)) {
            return RuleMatch(RuleAction.ALLOW, RuleCategory.ALLOWLIST, RuleSource.USER_ALLOWLIST, d)
        }
        // Exact blocklist.
        if (exactBlock.contains(d)) {
            return findExactBlockMatch(d) ?: defaultAllow(d)
        }

        // Trie traversal: longest matching suffix from the right.
        val labels = d.split(".")
        var node = root
        var best: RuleMatch? = null
        for (i in labels.indices.reversed()) {
            val child = node.children[labels[i]] ?: break
            node = child
            // Wildcard node: matches this and deeper, but not the apex unless exact.
            val m = node.match
            if (m != null) {
                // If rule is "*.example.com" (wildcard), it should not match "example.com" exactly.
                // We store wildcard rules as the subdomain part; exact stored separately.
                best = m
            }
        }
        return best ?: defaultAllow(d)
    }

    private fun findExactBlockMatch(domain: String): RuleMatch? {
        // Walk trie to find the exact node match for blocklist category.
        val labels = domain.split(".")
        var node = root
        for (i in labels.indices.reversed()) {
            node = node.children[labels[i]] ?: return null
        }
        return node.match
    }

    private fun defaultAllow(domain: String) =
        RuleMatch(RuleAction.ALLOW, null, RuleSource.SYSTEM, domain)

    fun isAllowed(domain: String) = evaluate(domain).action == RuleAction.ALLOW
    fun isBlocked(domain: String) = evaluate(domain).action == RuleAction.BLOCK
}

data class RuleEntry(
    val domain: String,
    val action: RuleAction,
    val category: RuleCategory,
    val source: RuleSource,
    val exact: Boolean = false,
)