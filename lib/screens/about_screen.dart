import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ThemeAppBar(title: 'About'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ThemeCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.shield, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('NetShield', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Version 1.0.0', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ThemeSectionHeader(title: 'What it does', actionLabel: ''),
          const SizedBox(height: 8),
          ThemeCard(
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'NetShield runs a local VPN on your device using Android VpnService. '
                'DNS queries are intercepted, checked against your rules and blocklists, and '
                'blocked or forwarded to your chosen upstream resolver.\n\n'
                'DNS filtering only blocks domains identified at the DNS level. '
                'It cannot block all advertisements or content embedded within pages.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          ThemeSectionHeader(title: 'Privacy', actionLabel: ''),
          const SizedBox(height: 8),
          ThemeCard(
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'The app operates entirely locally. DNS logs are stored only on your device '
                'and are never sent to an external server. No analytics are collected.\n\n'
                'DNS queries for allowed domains are forwarded to your selected upstream '
                'resolver, which may log them according to its own privacy policy.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          ThemeSectionHeader(title: 'Limitations', actionLabel: ''),
          const SizedBox(height: 8),
          ThemeCard(
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '• Requires Android VPN permission (no root needed).\n'
                '• Per-app attribution is only shown where Android APIs reliably provide it.\n'
                '• DoH and DoT protocols are planned for future releases.\n'
                '• DNS filtering does not block ads served from the same domain as content.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}