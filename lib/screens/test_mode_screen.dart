import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';
import '../providers/providers.dart';

class TestModeScreen extends ConsumerStatefulWidget {
  const TestModeScreen({super.key});

  @override
  ConsumerState<TestModeScreen> createState() => _TestModeScreenState();
}

class _TestModeScreenState extends ConsumerState<TestModeScreen> {
  final _domainCtrl = TextEditingController();
  Map<String, dynamic>? _dnsResult;
  Map<String, dynamic>? _ruleResult;
  bool _loading = false;

  @override
  void dispose() {
    _domainCtrl.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    final domain = _domainCtrl.text.trim().toLowerCase();
    if (domain.isEmpty) return;
    setState(() => _loading = true);
    final activeId = ref.read(activeResolverProvider);
    final resolvers = ref.read(resolversProvider);
    final resolver = resolvers.firstWhere((r) => r.id == activeId, orElse: () => resolvers.first);
    final dns = await ref.read(vpnBridgeProvider).testDomain(domain, host: resolver.host, port: resolver.port);
    final rule = await ref.read(vpnBridgeProvider).testRule(domain);
    setState(() {
      _dnsResult = dns;
      _ruleResult = rule;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ThemeAppBar(title: 'Test Mode'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ThemeTextField(
              controller: _domainCtrl,
              labelText: 'Domain to test',
              hintText: 'ads.example.com',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ThemeButton(
                label: 'Run test',
                icon: Icons.play_arrow,
                onPressed: _loading ? null : _runTest,
              ),
            ),
            const SizedBox(height: 20),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_ruleResult != null) ...[
              ThemeSectionHeader(title: 'Rule match', actionLabel: ''),
              const SizedBox(height: 8),
              ThemeCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ResultRow(label: 'Action', value: _ruleResult!['action'] ?? ''),
                      _ResultRow(label: 'Category', value: _ruleResult!['category'] ?? ''),
                      _ResultRow(label: 'Source', value: _ruleResult!['source'] ?? ''),
                      _ResultRow(label: 'Matched rule', value: _ruleResult!['matchedRule'] ?? ''),
                    ],
                  ),
                ),
              ),
            ],
            if (_dnsResult != null) ...[
              const SizedBox(height: 20),
              ThemeSectionHeader(title: 'DNS response', actionLabel: ''),
              const SizedBox(height: 8),
              ThemeCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ResultRow(label: 'Decision', value: (_dnsResult!['blocked'] as bool?) == true ? 'BLOCKED' : 'ALLOWED'),
                      _ResultRow(label: 'IP addresses', value: (_dnsResult!['ips'] as List?)?.join(', ') ?? ''),
                      _ResultRow(label: 'Response time', value: '${_dnsResult!['responseTimeMs']} ms'),
                      _ResultRow(label: 'Cache', value: (_dnsResult!['cacheHit'] as bool?) == true ? 'hit' : 'miss'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Expanded(child: Text(value, textAlign: TextAlign.end, style: Theme.of(context).textTheme.titleSmall)),
        ],
      ),
    );
  }
}