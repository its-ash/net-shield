import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/default_blocklist.dart';
import '../models/models.dart';

/// Local persistence for settings, rules, blocklists, resolvers, and logs.
/// Uses SharedPreferences for structured data and a JSON file for logs
/// (bounded by retention policy).
class StorageService {
  static const _keyAllowlist = 'allowlist';
  static const _keyBlocklist = 'blocklist';
  static const _keySources = 'blocklist_sources';
  static const _keyResolvers = 'resolvers';
  static const _keyAppRules = 'app_rules';
  static const _keyActiveResolver = 'active_resolver';
  static const _keyRetention = 'log_retention_days';
  static const _keyDarkMode = 'dark_mode';
  static const _keyDefaultsSeeded = 'defaults_seeded';
  static const _keyRemoteVersion = 'remote_blocklist_version';
  static const _keyLastUpdate = 'remote_blocklist_last_update';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _seedDefaults();
  }

  // ---- Remote blocklist version tracking ----
  String getRemoteBlocklistVersion() => _prefs.getString(_keyRemoteVersion) ?? '';
  Future<void> setRemoteBlocklistVersion(String v) => _prefs.setString(_keyRemoteVersion, v);
  DateTime? getRemoteBlocklistLastUpdate() {
    final s = _prefs.getString(_keyLastUpdate);
    return s != null ? DateTime.tryParse(s) : null;
  }
  Future<void> setRemoteBlocklistLastUpdate(DateTime dt) =>
      _prefs.setString(_keyLastUpdate, dt.toIso8601String());

  /// On first launch, populate the custom blocklist with the shipped defaults.
  Future<void> _seedDefaults() async {
    if (_prefs.getBool(_keyDefaultsSeeded) == true) return;
    final existing = _prefs.getStringList(_keyBlocklist);
    if (existing == null || existing.isEmpty) {
      await _prefs.setStringList(
        _keyBlocklist,
        defaultBlocklist.map((r) => jsonEncode(r.toMap())).toList(),
      );
    }
    await _prefs.setBool(_keyDefaultsSeeded, true);
  }

  // ---- Allowlist ----
  List<RuleEntry> getAllowlist() {
    final raw = _prefs.getStringList(_keyAllowlist) ?? [];
    return raw
        .map((s) {
          try {
            return RuleEntry.fromMap(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<RuleEntry>()
        .where((r) => r.enabled)
        .toList();
  }

  Future<void> saveAllowlist(List<RuleEntry> rules) async {
    await _prefs.setStringList(
      _keyAllowlist,
      rules.map((r) => jsonEncode(r.toMap())).toList(),
    );
  }

  // ---- Custom blocklist ----
  List<RuleEntry> getCustomBlocklist() {
    final raw = _prefs.getStringList(_keyBlocklist) ?? [];
    return raw
        .map((s) {
          try {
            return RuleEntry.fromMap(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<RuleEntry>()
        .toList();
  }

  Future<void> saveCustomBlocklist(List<RuleEntry> rules) async {
    await _prefs.setStringList(
      _keyBlocklist,
      rules.map((r) => jsonEncode(r.toMap())).toList(),
    );
  }

  // ---- Blocklist sources ----
  List<BlocklistSource> getBlocklistSources() {
    final raw = _prefs.getStringList(_keySources) ?? [];
    return raw
        .map((s) {
          try {
            return BlocklistSource.fromMap(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<BlocklistSource>()
        .toList();
  }

  Future<void> saveBlocklistSources(List<BlocklistSource> sources) async {
    await _prefs.setStringList(
      _keySources,
      sources.map((s) => jsonEncode(s.toMap())).toList(),
    );
  }

  // ---- Resolvers ----
  List<DnsResolverConfig> getResolvers() {
    final raw = _prefs.getStringList(_keyResolvers) ?? [];
    if (raw.isEmpty) return [DnsResolverConfig.system];
    return raw
        .map((s) {
          try {
            return DnsResolverConfig.fromMap(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<DnsResolverConfig>()
        .toList();
  }

  Future<void> saveResolvers(List<DnsResolverConfig> resolvers) async {
    await _prefs.setStringList(
      _keyResolvers,
      resolvers.map((r) => jsonEncode(r.toMap())).toList(),
    );
  }

  String getActiveResolverId() => _prefs.getString(_keyActiveResolver) ?? 'system';
  Future<void> setActiveResolverId(String id) => _prefs.setString(_keyActiveResolver, id);

  // ---- App rules ----
  List<AppRule> getAppRules() {
    final raw = _prefs.getStringList(_keyAppRules) ?? [];
    return raw
        .map((s) {
          try {
            return AppRule.fromMap(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<AppRule>()
        .toList();
  }

  Future<void> saveAppRules(List<AppRule> rules) async {
    await _prefs.setStringList(
      _keyAppRules,
      rules.map((r) => jsonEncode(r.toMap())).toList(),
    );
  }

  // ---- Settings ----
  int getRetentionDays() => _prefs.getInt(_keyRetention) ?? 7;
  Future<void> setRetentionDays(int days) => _prefs.setInt(_keyRetention, days);

  bool getDarkMode() => _prefs.getBool(_keyDarkMode) ?? false;
  Future<void> setDarkMode(bool v) => _prefs.setBool(_keyDarkMode, v);

  // ---- Import / Export ----
  Future<Map<String, dynamic>> exportAll() async {
    return {
      'version': 1,
      'allowlist': getAllowlist().map((r) => r.domain).toList(),
      'blocklist': getCustomBlocklist().map((r) => r.domain).toList(),
      'blocklistSources': getBlocklistSources().map((s) => s.toMap()).toList(),
      'resolvers': getResolvers().map((r) => r.toMap()).toList(),
      'activeResolver': getActiveResolverId(),
      'appRules': getAppRules().map((r) => r.toMap()).toList(),
      'settings': {
        'retentionDays': getRetentionDays(),
        'darkMode': getDarkMode(),
      },
    };
  }

  Future<void> importAll(Map<String, dynamic> data) async {
    final allow = (data['allowlist'] as List?)
            ?.map((e) => RuleEntry(domain: e as String, category: RuleCategory.custom))
            .toList() ??
        [];
    final block = (data['blocklist'] as List?)
            ?.map((e) => RuleEntry(domain: e as String))
            .toList() ??
        [];
    await saveAllowlist(allow);
    await saveCustomBlocklist(block);

    if (data['blocklistSources'] != null) {
      final sources = (data['blocklistSources'] as List)
          .map((s) => BlocklistSource.fromMap(Map<String, dynamic>.from(s as Map)))
          .toList();
      await saveBlocklistSources(sources);
    }
    if (data['resolvers'] != null) {
      final resolvers = (data['resolvers'] as List)
          .map((s) => DnsResolverConfig.fromMap(Map<String, dynamic>.from(s as Map)))
          .toList();
      await saveResolvers(resolvers);
    }
    if (data['activeResolver'] is String) {
      await setActiveResolverId(data['activeResolver'] as String);
    }
    if (data['appRules'] != null) {
      final rules = (data['appRules'] as List)
          .map((s) => AppRule.fromMap(Map<String, dynamic>.from(s as Map)))
          .toList();
      await saveAppRules(rules);
    }
    if (data['settings'] is Map) {
      final s = Map<String, dynamic>.from(data['settings'] as Map);
      if (s['retentionDays'] is int) await setRetentionDays(s['retentionDays'] as int);
      if (s['darkMode'] is bool) await setDarkMode(s['darkMode'] as bool);
    }
  }

  // ---- Logs (file-based, bounded) ----
  Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/dns_logs.jsonl');
  }

  Future<void> appendLog(QueryLogEntry entry) async {
    final retention = getRetentionDays();
    if (retention == 0) return; // disabled
    final file = await _logFile();
    final sink = file.openWrite(mode: FileMode.append);
    sink.writeln(jsonEncode({
      'ts': entry.timestamp.millisecondsSinceEpoch,
      'domain': entry.domain,
      'type': entry.queryType,
      'app': entry.sourceApp,
      'action': entry.action.name,
      'category': entry.category?.name,
      'source': entry.source,
      'rule': entry.matchedRule,
    }));
    await sink.flush();
    await sink.close();
  }

  Future<List<QueryLogEntry>> loadLogs({int limit = 500}) async {
    final file = await _logFile();
    if (!await file.exists()) return [];
    final lines = await file.readAsLines();
    final cutoff = getRetentionDays();
    final now = DateTime.now();
    final keep = cutoff == 0
        ? null
        : now.subtract(Duration(days: cutoff));
    final out = <QueryLogEntry>[];
    for (final line in lines.reversed) {
      if (out.length >= limit) break;
      if (line.trim().isEmpty) continue;
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        final ts = DateTime.fromMillisecondsSinceEpoch(m['ts'] as int? ?? 0);
        if (keep != null && ts.isBefore(keep)) continue;
        out.add(QueryLogEntry(
          timestamp: ts,
          domain: m['domain'] as String? ?? '',
          queryType: m['type'] as int? ?? 0,
          sourceApp: m['app'] as String?,
          action: (m['action'] as String?) == 'blocked'
              ? QueryAction.blocked
              : QueryAction.allowed,
          category: RuleCategory.values.firstWhere(
            (c) => c.name == (m['category'] as String?),
            orElse: () => RuleCategory.custom,
          ),
          source: m['source'] as String? ?? '',
          matchedRule: m['rule'] as String? ?? '',
        ));
      } catch (_) {}
    }
    return out;
  }

  Future<void> clearLogs() async {
    final file = await _logFile();
    if (await file.exists()) await file.writeAsString('');
  }

  // ---- Per-day statistics persistence ----
  Future<Map<String, int>> getDayStats(DateTime day) async {
    final key = 'day_${day.year}_${day.month}_${day.day}';
    final raw = _prefs.getString(key);
    if (raw == null) return {'total': 0, 'blocked': 0, 'allowed': 0};
    try {
      return Map<String, int>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {'total': 0, 'blocked': 0, 'allowed': 0};
    }
  }

  Future<void> incrementDayStats(DateTime day, {required bool blocked}) async {
    final stats = await getDayStats(day);
    stats['total'] = (stats['total'] ?? 0) + 1;
    if (blocked) {
      stats['blocked'] = (stats['blocked'] ?? 0) + 1;
    } else {
      stats['allowed'] = (stats['allowed'] ?? 0) + 1;
    }
    final key = 'day_${day.year}_${day.month}_${day.day}';
    await _prefs.setString(key, jsonEncode(stats));
  }

  Future<void> pruneOldStats() async {
    final retention = getRetentionDays();
    if (retention == 0) return;
    final cutoff = DateTime.now().subtract(Duration(days: retention));
    final keys = _prefs.getKeys().where((k) => k.startsWith('day_'));
    for (final k in keys) {
      final parts = k.substring(4).split('_');
      if (parts.length == 3) {
        try {
          final d = DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
          if (d.isBefore(cutoff)) await _prefs.remove(k);
        } catch (_) {}
      }
    }
  }
}