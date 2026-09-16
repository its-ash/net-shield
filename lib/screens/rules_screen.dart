import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:theme/theme.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _RuleTile(icon: Icons.list, title: 'Blocklists', subtitle: 'Imported blocklist sources', route: '/blocklists'),
      _RuleTile(icon: Icons.check_circle_outline, title: 'Allowlist', subtitle: 'Whitelisted domains (always allowed)', route: '/allowlist'),
      _RuleTile(icon: Icons.rule, title: 'Custom Rules', subtitle: 'Manually blocked domains', route: '/custom-rules'),
      _RuleTile(icon: Icons.apps, title: 'App Rules', subtitle: 'Per-app bypass / protection', route: '/apps'),
      _RuleTile(icon: Icons.dns, title: 'DNS Servers', subtitle: 'Upstream resolver configuration', route: '/dns-servers'),
      _RuleTile(icon: Icons.science_outlined, title: 'Test Mode', subtitle: 'Test a domain against the firewall', route: '/test'),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ThemeSectionHeader(title: 'Rules & Filtering', actionLabel: ''),
        const SizedBox(height: 8),
        ThemeCard(
          child: Column(
            children: [
              for (final t in tiles) ...[
                ThemeListTile(
                  leading: Icon(t.icon),
                  title: t.title,
                  subtitle: t.subtitle,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(t.route),
                ),
                if (t != tiles.last) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RuleTile {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  const _RuleTile({required this.icon, required this.title, required this.subtitle, required this.route});
}