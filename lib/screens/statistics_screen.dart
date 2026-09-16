import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:theme/theme.dart';
import '../providers/providers.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protection = ref.watch(protectionProvider);
    final stats = protection.stats;
    final fmt = NumberFormat.decimalPattern();
    final blockRate = stats.blockPercentage.toStringAsFixed(1);

    return Scaffold(
      appBar: ThemeAppBar(title: 'Statistics'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ThemeSectionHeader(title: 'Current session', actionLabel: ''),
          const SizedBox(height: 8),
          _StatCard(label: 'Total queries', value: fmt.format(stats.total)),
          _StatCard(label: 'Blocked', value: fmt.format(stats.blocked), color: Theme.of(context).colorScheme.error),
          _StatCard(label: 'Allowed', value: fmt.format(stats.allowed)),
          _StatCard(label: 'Block rate', value: '$blockRate%'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Cache hits', value: fmt.format(stats.cacheHits))),
              const SizedBox(width: 8),
              Expanded(child: _StatCard(label: 'Cache misses', value: fmt.format(stats.cacheMisses))),
            ],
          ),
          const SizedBox(height: 20),
          ThemeSectionHeader(title: 'Most blocked domains', actionLabel: ''),
          const SizedBox(height: 8),
          const ThemeEmptyState(icon: Icons.bar_chart, title: 'No data yet', subtitle: 'Start protection to collect statistics.'),
          const SizedBox(height: 20),
          ThemeSectionHeader(title: 'Most active apps', actionLabel: ''),
          const SizedBox(height: 8),
          const ThemeEmptyState(icon: Icons.apps, title: 'No app data', subtitle: 'Per-app attribution appears here when available.'),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatCard({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ThemeCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}