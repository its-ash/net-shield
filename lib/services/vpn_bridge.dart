import 'dart:async';
import 'package:flutter/services.dart';
import '../models/models.dart';

/// Platform-channel bridge to the native Kotlin VpnService + DNS engine.
class VpnBridge {
  static const _method = MethodChannel('com.itsash.local_dns_firewall/vpn');
  static const _logEvent = EventChannel('com.itsash.local_dns_firewall/logs');

  static final VpnBridge instance = VpnBridge._();
  VpnBridge._();

  final _logController = StreamController<QueryLogEntry>.broadcast();
  Stream<QueryLogEntry> get logStream => _logController.stream;

  void startListening() {
    _logEvent.receiveBroadcastStream().listen(
      (e) => _logController.add(QueryLogEntry.fromMap(e as Map<dynamic, dynamic>)),
      onError: (_) {},
    );
  }

  Future<bool> prepareVpn() async {
    final r = await _method.invokeMethod<bool>('prepareVpn');
    return r ?? false;
  }

  Future<void> startVpn({required String resolverName, required String host, required int port}) async {
    await _method.invokeMethod<bool>('startVpn', {
      'resolverName': resolverName,
      'host': host,
      'port': port,
    });
  }

  Future<void> stopVpn() async {
    await _method.invokeMethod<bool>('stopVpn');
  }

  Future<bool> isRunning() async {
    final r = await _method.invokeMethod<bool>('isRunning');
    return r ?? false;
  }

  Future<VpnStats> getStats() async {
    final r = await _method.invokeMethod<Map>('getStats');
    if (r == null) return const VpnStats();
    return VpnStats.fromMap(r);
  }

  Future<void> syncRules({
    required List<Map<String, dynamic>> allowlist,
    required List<Map<String, dynamic>> blocklist,
  }) async {
    await _method.invokeMethod<bool>('syncRules', {
      'allowlist': allowlist,
      'blocklist': blocklist,
    });
  }

  Future<void> clearCache() async {
    await _method.invokeMethod<bool>('clearCache');
  }

  Future<Map<String, dynamic>> testDomain(String domain, {String host = '1.1.1.1', int port = 53}) async {
    final r = await _method.invokeMethod<Map>('testDomain', {
      'domain': domain,
      'host': host,
      'port': port,
    });
    return Map<String, dynamic>.from(r ?? {});
  }

  Future<Map<String, dynamic>> testRule(String domain) async {
    final r = await _method.invokeMethod<Map>('testRule', {'domain': domain});
    return Map<String, dynamic>.from(r ?? {});
  }
}