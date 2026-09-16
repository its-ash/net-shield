import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';
import '../providers/providers.dart';

class DevDiagnosticsScreen extends ConsumerWidget {
  const DevDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protection = ref.watch(protectionProvider);
    final stats = protection.stats;
    final memMb = (ProcessInfo.currentRss / 1024 / 1024).toStringAsFixed(1);

    return Scaffold(
      appBar: ThemeAppBar(title: 'Developer Diagnostics'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ThemeSectionHeader(title: 'Engine status', actionLabel: ''),
          const SizedBox(height: 8),
          _DiagRow(label: 'VPN status', value: protection.isOn ? 'Running' : 'Stopped'),
          _DiagRow(label: 'DNS engine', value: protection.isOn ? 'Active' : 'Idle'),
          _DiagRow(label: 'Resolver', value: stats.resolver),
          _DiagRow(label: 'Last DNS error', value: stats.lastError.isEmpty ? 'None' : stats.lastError),
          const SizedBox(height: 20),
          ThemeSectionHeader(title: 'Counts', actionLabel: ''),
          const SizedBox(height: 8),
          _DiagRow(label: 'Query count', value: '${stats.total}'),
          _DiagRow(label: 'Rule count', value: '${stats.ruleCount}'),
          _DiagRow(label: 'Cache size', value: '${stats.cacheSize}'),
          _DiagRow(label: 'Cache hits', value: '${stats.cacheHits}'),
          _DiagRow(label: 'Cache misses', value: '${stats.cacheMisses}'),
          _DiagRow(label: 'Memory (RSS)', value: '$memMb MB'),
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  final String label;
  final String value;
  const _DiagRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ThemeCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(value, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}