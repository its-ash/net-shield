/// Domain models for the Local DNS Firewall.
library;

enum RuleCategory { ads, trackers, malware, telemetry, custom }

enum RuleAction { allow, block }

enum QueryAction { blocked, allowed }

class RuleEntry {
  final String domain;
  final RuleCategory category;
  final bool exact;
  final bool enabled;

  const RuleEntry({
    required this.domain,
    this.category = RuleCategory.custom,
    this.exact = false,
    this.enabled = true,
  });

  Map<String, dynamic> toMap() => {
        'domain': domain,
        'category': category.name,
        'exact': exact,
        'enabled': enabled,
      };

  factory RuleEntry.fromMap(Map<String, dynamic> m) => RuleEntry(
        domain: m['domain'] as String? ?? '',
        category: RuleCategory.values.firstWhere(
          (c) => c.name == (m['category'] as String?),
          orElse: () => RuleCategory.custom,
        ),
        exact: m['exact'] as bool? ?? false,
        enabled: m['enabled'] as bool? ?? true,
      );

  RuleEntry copyWith({
    String? domain,
    RuleCategory? category,
    bool? exact,
    bool? enabled,
  }) =>
      RuleEntry(
        domain: domain ?? this.domain,
        category: category ?? this.category,
        exact: exact ?? this.exact,
        enabled: enabled ?? this.enabled,
      );
}

class BlocklistSource {
  final String id;
  final String name;
  final String? url;
  final String? localPath;
  final int ruleCount;
  final DateTime? lastUpdated;
  final bool enabled;
  final String updateStatus; // 'idle' | 'updating' | 'success' | 'error'

  const BlocklistSource({
    required this.id,
    required this.name,
    this.url,
    this.localPath,
    this.ruleCount = 0,
    this.lastUpdated,
    this.enabled = true,
    this.updateStatus = 'idle',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'url': url,
        'localPath': localPath,
        'ruleCount': ruleCount,
        'lastUpdated': lastUpdated?.toIso8601String(),
        'enabled': enabled,
        'updateStatus': updateStatus,
      };

  factory BlocklistSource.fromMap(Map<String, dynamic> m) => BlocklistSource(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        url: m['url'] as String?,
        localPath: m['localPath'] as String?,
        ruleCount: (m['ruleCount'] as num?)?.toInt() ?? 0,
        lastUpdated: m['lastUpdated'] != null
            ? DateTime.tryParse(m['lastUpdated'] as String)
            : null,
        enabled: m['enabled'] as bool? ?? true,
        updateStatus: m['updateStatus'] as String? ?? 'idle',
      );

  BlocklistSource copyWith({
    String? name,
    String? url,
    String? localPath,
    int? ruleCount,
    DateTime? lastUpdated,
    bool? enabled,
    String? updateStatus,
  }) =>
      BlocklistSource(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        localPath: localPath ?? this.localPath,
        ruleCount: ruleCount ?? this.ruleCount,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        enabled: enabled ?? this.enabled,
        updateStatus: updateStatus ?? this.updateStatus,
      );
}

class DnsResolverConfig {
  final String id;
  final String name;
  final String protocol; // 'system' | 'udp' | 'tcp' | 'dot' | 'doh'
  final String host;
  final int port;

  const DnsResolverConfig({
    required this.id,
    required this.name,
    this.protocol = 'udp',
    this.host = '1.1.1.1',
    this.port = 53,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'protocol': protocol,
        'host': host,
        'port': port,
      };

  factory DnsResolverConfig.fromMap(Map<String, dynamic> m) => DnsResolverConfig(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        protocol: m['protocol'] as String? ?? 'udp',
        host: m['host'] as String? ?? '1.1.1.1',
        port: (m['port'] as num?)?.toInt() ?? 53,
      );

  static const system = DnsResolverConfig(
    id: 'system',
    name: 'System default',
    protocol: 'system',
    host: '1.1.1.1',
    port: 53,
  );
}

class AppRule {
  final String packageName;
  final String appName;
  final bool bypass; // true = bypass protection, false = protected

  const AppRule({
    required this.packageName,
    required this.appName,
    this.bypass = false,
  });

  Map<String, dynamic> toMap() => {
        'packageName': packageName,
        'appName': appName,
        'bypass': bypass,
      };

  factory AppRule.fromMap(Map<String, dynamic> m) => AppRule(
        packageName: m['packageName'] as String,
        appName: m['appName'] as String? ?? '',
        bypass: m['bypass'] as bool? ?? false,
      );
}

class QueryLogEntry {
  final DateTime timestamp;
  final String domain;
  final int queryType;
  final String? sourceApp;
  final QueryAction action;
  final RuleCategory? category;
  final String source;
  final String matchedRule;

  QueryLogEntry({
    required this.timestamp,
    required this.domain,
    required this.queryType,
    this.sourceApp,
    required this.action,
    this.category,
    required this.source,
    required this.matchedRule,
  });

  factory QueryLogEntry.fromMap(Map<dynamic, dynamic> m) {
    final actionStr = (m['action'] as String?)?.toLowerCase() ?? 'allowed';
    return QueryLogEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (m['timestamp'] as num?)?.toInt() ?? 0,
      ),
      domain: m['domain'] as String? ?? '',
      queryType: (m['queryType'] as num?)?.toInt() ?? 0,
      sourceApp: m['sourceApp'] as String?,
      action: actionStr == 'block' ? QueryAction.blocked : QueryAction.allowed,
      category: RuleCategory.values.firstWhere(
        (c) => c.name == (m['category'] as String?)?.toLowerCase(),
        orElse: () => RuleCategory.custom,
      ),
      source: m['source'] as String? ?? '',
      matchedRule: m['matchedRule'] as String? ?? '',
    );
  }
}

class VpnStats {
  final int total;
  final int blocked;
  final int allowed;
  final int cacheHits;
  final int cacheMisses;
  final int cacheSize;
  final int ruleCount;
  final String resolver;
  final String lastError;

  const VpnStats({
    this.total = 0,
    this.blocked = 0,
    this.allowed = 0,
    this.cacheHits = 0,
    this.cacheMisses = 0,
    this.cacheSize = 0,
    this.ruleCount = 0,
    this.resolver = 'System default',
    this.lastError = '',
  });

  factory VpnStats.fromMap(Map<dynamic, dynamic> m) => VpnStats(
        total: (m['total'] as num?)?.toInt() ?? 0,
        blocked: (m['blocked'] as num?)?.toInt() ?? 0,
        allowed: (m['allowed'] as num?)?.toInt() ?? 0,
        cacheHits: (m['cacheHits'] as num?)?.toInt() ?? 0,
        cacheMisses: (m['cacheMisses'] as num?)?.toInt() ?? 0,
        cacheSize: (m['cacheSize'] as num?)?.toInt() ?? 0,
        ruleCount: (m['ruleCount'] as num?)?.toInt() ?? 0,
        resolver: m['resolver'] as String? ?? 'System default',
        lastError: m['lastError'] as String? ?? '',
      );

  double get blockPercentage =>
      total == 0 ? 0 : (blocked / total * 100);

  int get queriesPerMinute => 0; // computed in provider from time window
}