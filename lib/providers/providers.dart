import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../services/vpn_bridge.dart';
import '../services/blocklist_update_service.dart';

final storageProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

final vpnBridgeProvider = Provider<VpnBridge>((ref) => VpnBridge.instance);

// ---- Protection status ----
class ProtectionState {
  final bool isOn;
  final bool isStarting;
  final VpnStats stats;
  final String error;

  const ProtectionState({
    this.isOn = false,
    this.isStarting = false,
    this.stats = const VpnStats(),
    this.error = '',
  });

  ProtectionState copyWith({
    bool? isOn,
    bool? isStarting,
    VpnStats? stats,
    String? error,
  }) =>
      ProtectionState(
        isOn: isOn ?? this.isOn,
        isStarting: isStarting ?? this.isStarting,
        stats: stats ?? this.stats,
        error: error ?? this.error,
      );
}

class ProtectionNotifier extends StateNotifier<ProtectionState> {
  final VpnBridge _vpn;
  final StorageService _storage;
  Timer? _pollTimer;

  ProtectionNotifier(this._vpn, this._storage) : super(const ProtectionState()) {
    _vpn.startListening();
    _checkRunning();
  }

  Future<void> _checkRunning() async {
    final running = await _vpn.isRunning();
    if (running) {
      state = state.copyWith(isOn: true);
      _startPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStats());
  }

  Future<void> _refreshStats() async {
    if (!state.isOn) return;
    final stats = await _vpn.getStats();
    state = state.copyWith(stats: stats, error: stats.lastError);
  }

  Future<void> startProtection() async {
    state = state.copyWith(isStarting: true, error: '');
    try {
      final granted = await _vpn.prepareVpn();
      if (!granted) {
        state = state.copyWith(isStarting: false, error: 'VPN permission denied');
        return;
      }
      final resolvers = _storage.getResolvers();
      final activeId = _storage.getActiveResolverId();
      final resolver = resolvers.firstWhere(
        (r) => r.id == activeId,
        orElse: () => DnsResolverConfig.system,
      );
      // Sync rules before starting.
      final allow = _storage.getAllowlist();
      final block = _storage.getCustomBlocklist();
      final enabledSources = _storage.getBlocklistSources().where((s) => s.enabled);
      final allBlock = <Map<String, dynamic>>[
        ...block.map((r) => r.toMap()),
        ...enabledSources.expand((s) => s.localPath != null
            ? <Map<String, dynamic>>[] // parsed rules are applied at native layer via source files
            : <Map<String, dynamic>>[]),
      ];
      await _vpn.syncRules(
        allowlist: allow.map((r) => r.toMap()).toList(),
        blocklist: allBlock,
      );
      await _vpn.startVpn(
        resolverName: resolver.name,
        host: resolver.host,
        port: resolver.port,
      );
      state = state.copyWith(isOn: true, isStarting: false);
      _startPolling();
    } catch (e) {
      state = state.copyWith(isStarting: false, error: e.toString());
    }
  }

  Future<void> stopProtection() async {
    await _vpn.stopVpn();
    _pollTimer?.cancel();
    state = const ProtectionState(isOn: false);
  }

  Future<void> refreshStats() => _refreshStats();

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final protectionProvider =
    StateNotifierProvider<ProtectionNotifier, ProtectionState>((ref) {
  final storage = ref.read(storageProvider);
  final vpn = ref.read(vpnBridgeProvider);
  return ProtectionNotifier(vpn, storage);
});

// ---- Allowlist ----
class AllowlistNotifier extends StateNotifier<List<RuleEntry>> {
  final StorageService _storage;
  final VpnBridge _vpn;
  AllowlistNotifier(this._storage, this._vpn) : super([]) {
    state = _storage.getAllowlist();
  }

  void add(RuleEntry entry) {
    state = [...state, entry];
    _persist();
  }

  void update(int index, RuleEntry entry) {
    state = [...state]..[index] = entry;
    _persist();
  }

  void removeAt(int index) {
    state = [...state]..removeAt(index);
    _persist();
  }

  void _persist() {
    _storage.saveAllowlist(state);
    _vpn.syncRules(
      allowlist: state.map((r) => r.toMap()).toList(),
      blocklist: _storage.getCustomBlocklist().map((r) => r.toMap()).toList(),
    );
  }
}

final allowlistProvider =
    StateNotifierProvider<AllowlistNotifier, List<RuleEntry>>((ref) {
  return AllowlistNotifier(ref.read(storageProvider), ref.read(vpnBridgeProvider));
});

// ---- Custom blocklist ----
class CustomBlocklistNotifier extends StateNotifier<List<RuleEntry>> {
  final StorageService _storage;
  final VpnBridge _vpn;
  CustomBlocklistNotifier(this._storage, this._vpn) : super([]) {
    state = _storage.getCustomBlocklist();
  }

  void add(RuleEntry entry) {
    state = [...state, entry];
    _persist();
  }

  void update(int index, RuleEntry entry) {
    state = [...state]..[index] = entry;
    _persist();
  }

  void removeAt(int index) {
    state = [...state]..removeAt(index);
    _persist();
  }

  void toggleEnabled(int index) {
    final e = state[index];
    state = [...state]..[index] = e.copyWith(enabled: !e.enabled);
    _persist();
  }

  void _persist() {
    _storage.saveCustomBlocklist(state);
    _vpn.syncRules(
      allowlist: _storage.getAllowlist().map((r) => r.toMap()).toList(),
      blocklist: state.map((r) => r.toMap()).toList(),
    );
  }
}

final customBlocklistProvider =
    StateNotifierProvider<CustomBlocklistNotifier, List<RuleEntry>>((ref) {
  return CustomBlocklistNotifier(ref.read(storageProvider), ref.read(vpnBridgeProvider));
});

// ---- Blocklist sources ----
class BlocklistSourcesNotifier extends StateNotifier<List<BlocklistSource>> {
  final StorageService _storage;
  BlocklistSourcesNotifier(this._storage) : super([]) {
    state = _storage.getBlocklistSources();
  }

  void add(BlocklistSource source) {
    state = [...state, source];
    _persist();
  }

  void update(int index, BlocklistSource source) {
    state = [...state]..[index] = source;
    _persist();
  }

  void removeAt(int index) {
    state = [...state]..removeAt(index);
    _persist();
  }

  void toggleEnabled(int index) {
    final s = state[index];
    state = [...state]..[index] = s.copyWith(enabled: !s.enabled);
    _persist();
  }

  void _persist() => _storage.saveBlocklistSources(state);
}

final blocklistSourcesProvider =
    StateNotifierProvider<BlocklistSourcesNotifier, List<BlocklistSource>>((ref) {
  return BlocklistSourcesNotifier(ref.read(storageProvider));
});

// ---- Resolvers ----
class ResolversNotifier extends StateNotifier<List<DnsResolverConfig>> {
  final StorageService _storage;
  ResolversNotifier(this._storage) : super([]) {
    state = _storage.getResolvers();
  }

  void add(DnsResolverConfig r) {
    state = [...state, r];
    _persist();
  }

  void update(int index, DnsResolverConfig r) {
    state = [...state]..[index] = r;
    _persist();
  }

  void removeAt(int index) {
    state = [...state]..removeAt(index);
    _persist();
  }

  void _persist() => _storage.saveResolvers(state);
}

final resolversProvider =
    StateNotifierProvider<ResolversNotifier, List<DnsResolverConfig>>((ref) {
  return ResolversNotifier(ref.read(storageProvider));
});

final activeResolverProvider = StateProvider<String>((ref) {
  return ref.read(storageProvider).getActiveResolverId();
});

// ---- App rules ----
class AppRulesNotifier extends StateNotifier<List<AppRule>> {
  final StorageService _storage;
  AppRulesNotifier(this._storage) : super([]) {
    state = _storage.getAppRules();
  }

  void add(AppRule r) {
    state = [...state, r];
    _persist();
  }

  void update(int index, AppRule r) {
    state = [...state]..[index] = r;
    _persist();
  }

  void removeAt(int index) {
    state = [...state]..removeAt(index);
    _persist();
  }

  void _persist() => _storage.saveAppRules(state);
}

final appRulesProvider =
    StateNotifierProvider<AppRulesNotifier, List<AppRule>>((ref) {
  return AppRulesNotifier(ref.read(storageProvider));
});

// ---- Live log ----
final liveLogProvider = StreamProvider<QueryLogEntry>((ref) {
  return ref.read(vpnBridgeProvider).logStream;
});

// ---- Persisted logs ----
final persistedLogsProvider = FutureProvider.family<List<QueryLogEntry>, int>((ref, limit) async {
  return ref.read(storageProvider).loadLogs(limit: limit);
});

// ---- Settings ----
final retentionProvider = StateProvider<int>((ref) {
  return ref.read(storageProvider).getRetentionDays();
});

final darkModeProvider = StateProvider<bool>((ref) {
  return ref.read(storageProvider).getDarkMode();
});

// ---- Remote blocklist update ----
class BlocklistUpdateState {
  final String version;
  final DateTime? lastUpdated;
  final bool isChecking;
  final bool updated;
  const BlocklistUpdateState({
    this.version = '',
    this.lastUpdated,
    this.isChecking = false,
    this.updated = false,
  });
}

class BlocklistUpdateNotifier extends StateNotifier<BlocklistUpdateState> {
  final StorageService _storage;
  BlocklistUpdateNotifier(this._storage)
      : super(BlocklistUpdateState(
          version: _storage.getRemoteBlocklistVersion(),
          lastUpdated: _storage.getRemoteBlocklistLastUpdate(),
        ));

  Future<void> checkForUpdate() async {
    state = BlocklistUpdateState(
      version: _storage.getRemoteBlocklistVersion(),
      lastUpdated: _storage.getRemoteBlocklistLastUpdate(),
      isChecking: true,
    );
    final svc = BlocklistUpdateService(_storage);
    final didUpdate = await svc.checkAndUpdate();
    state = BlocklistUpdateState(
      version: _storage.getRemoteBlocklistVersion(),
      lastUpdated: _storage.getRemoteBlocklistLastUpdate(),
      isChecking: false,
      updated: didUpdate,
    );
  }
}

final blocklistUpdateProvider =
    StateNotifierProvider<BlocklistUpdateNotifier, BlocklistUpdateState>((ref) {
  return BlocklistUpdateNotifier(ref.read(storageProvider));
});