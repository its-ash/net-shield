import 'dart:convert';
import 'dart:io';
import '../models/models.dart';
import 'storage_service.dart';

/// Remote blocklist auto-updater.
///
/// On app launch, fetches the blocklist JSON from a raw GitHub URL.
/// Compares the remote `version` field against the last-applied version
/// stored in SharedPreferences. If newer, parses the rules and replaces
/// the stored custom blocklist, then persists the new version string.
///
/// The remote file is the canonical source of truth — the shipped
/// `default_blocklist.dart` is only the initial seed for first install.
class BlocklistUpdateService {
  static const _remoteUrl =
      'https://raw.githubusercontent.com/its-ash/net-shield/main/blocklist.json';

  final StorageService _storage;

  BlocklistUpdateService(this._storage);

  /// Fetch the remote blocklist and update if a newer version is available.
  /// Returns `true` if the blocklist was updated.
  Future<bool> checkAndUpdate() async {
    try {
      final json = await _fetchRemote();
      if (json == null) return false;

      final remoteVersion = json['version'] as String? ?? '';
      if (remoteVersion.isEmpty) return false;

      final currentVersion = _storage.getRemoteBlocklistVersion();
      if (remoteVersion == currentVersion) return false;

      final rulesList = json['rules'] as List? ?? [];
      final rules = rulesList
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return RuleEntry.fromMap(m);
          })
          .where((r) => r.domain.isNotEmpty)
          .toList();

      if (rules.isEmpty) return false;

      await _storage.saveCustomBlocklist(rules);
      await _storage.setRemoteBlocklistVersion(remoteVersion);
      await _storage.setRemoteBlocklistLastUpdate(DateTime.now());

      return true;
    } catch (_) {
      return false;
    }
  }

  String getRemoteVersion() => _storage.getRemoteBlocklistVersion();

  DateTime? getLastUpdate() => _storage.getRemoteBlocklistLastUpdate();

  Future<Map<String, dynamic>?> _fetchRemote() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_remoteUrl));
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}