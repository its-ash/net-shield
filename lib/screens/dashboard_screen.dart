import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:theme/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protection = ref.watch(protectionProvider);
    final stats = protection.stats;
    final fmt = NumberFormat.decimalPattern();
    final now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _ProtectionCard(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Total', value: fmt.format(stats.total))),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Blocked', value: fmt.format(stats.blocked), highlight: true)),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Allowed', value: fmt.format(stats.allowed))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Block rate', value: '${stats.blockPercentage.toStringAsFixed(1)}%')),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Rules', value: fmt.format(stats.ruleCount))),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(label: 'Cache', value: fmt.format(stats.cacheSize))),
          ],
        ),
        const SizedBox(height: 20),
        ThemeSectionHeader(title: "Today — ${DateFormat.MMMd().format(now)}", actionLabel: ''),
        const SizedBox(height: 8),
        const _TodayStats(),
        const SizedBox(height: 16),
        const _QuickActions(),
      ],
    );
  }
}

class _ProtectionCard extends ConsumerWidget {
  const _ProtectionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protection = ref.watch(protectionProvider);
    final notifier = ref.read(protectionProvider.notifier);
    final isOn = protection.isOn;
    final isStarting = protection.isStarting;

    return ThemeCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ThemeStatusPill(
                  label: isOn ? 'Protection Active' : 'Protection Off',
                  status: isOn ? ThemeStatus.success : ThemeStatus.error,
                  icon: isOn ? Icons.shield : Icons.shield_moon,
                ),
                if (protection.error.isNotEmpty)
                  ThemeStatusPill(label: 'Error', status: ThemeStatus.error, icon: Icons.error_outline),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              isOn ? '12,421' : '0',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text('Queries since start', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ThemeButton(
                label: isStarting
                    ? 'Starting…'
                    : (isOn ? 'STOP PROTECTION' : 'START PROTECTION'),
                variant: ThemeButtonVariant.filled,
                status: isOn ? ThemeButtonStatus.error : ThemeButtonStatus.success,
                icon: isOn ? Icons.stop : Icons.play_arrow,
                onPressed: isStarting
                    ? null
                    : () => isOn ? notifier.stopProtection() : notifier.startProtection(),
              ),
            ),
            if (protection.error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(protection.error, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _StatTile({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ThemeCard(
      color: highlight ? scheme.errorContainer.withValues(alpha: 0.3) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _TodayStats extends ConsumerWidget {
  const _TodayStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.read(storageProvider);
    return FutureBuilder<Map<String, int>>(
      future: storage.getDayStats(DateTime.now()),
      builder: (context, snap) {
        final stats = snap.data ?? {'total': 0, 'blocked': 0, 'allowed': 0};
        return ThemeCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _TodayRow(label: 'Queries today', value: '${stats['total'] ?? 0}'),
                _TodayRow(label: 'Blocked', value: '${stats['blocked'] ?? 0}'),
                _TodayRow(label: 'Allowed', value: '${stats['allowed'] ?? 0}'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TodayRow extends StatelessWidget {
  final String label;
  final String value;
  const _TodayRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThemeSectionHeader(title: 'Quick Actions', actionLabel: ''),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            QuickActionChip(label: 'Blocklists', icon: Icons.list, onTap: () => context.push('/blocklists')),
            QuickActionChip(label: 'Allowlist', icon: Icons.check_circle_outline, onTap: () => context.push('/allowlist')),
            QuickActionChip(label: 'Custom rules', icon: Icons.rule, onTap: () => context.push('/custom-rules')),
            QuickActionChip(label: 'Apps', icon: Icons.apps, onTap: () => context.push('/apps')),
            QuickActionChip(label: 'DNS servers', icon: Icons.dns, onTap: () => context.push('/dns-servers')),
            QuickActionChip(label: 'Statistics', icon: Icons.bar_chart, onTap: () => context.push('/statistics')),
          ],
        ),
      ],
    );
  }
}

class QuickActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const QuickActionChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: Icon(icon, size: 18),
      onPressed: onTap,
    );
  }
}