import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:theme/theme.dart';
import '../data/default_blocklist.dart';
import '../providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retention = ref.watch(retentionProvider);
    final darkMode = ref.watch(darkModeProvider);
    final storage = ref.read(storageProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ThemeSectionHeader(title: 'Protection', actionLabel: ''),
        const SizedBox(height: 8),
        ThemeCard(
          child: Column(
            children: [
              ThemeListTile(
                leading: const Icon(Icons.dns),
                title: 'DNS Servers',
                subtitle: 'Configure upstream resolvers',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/dns-servers'),
              ),
              const Divider(height: 1),
              ThemeListTile(
                leading: const Icon(Icons.science_outlined),
                title: 'Test Mode',
                subtitle: 'Test a domain against the firewall',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/test'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ThemeSectionHeader(title: 'Data retention', actionLabel: ''),
        const SizedBox(height: 8),
        ThemeCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DNS log retention: ${retention == 0 ? "Disabled" : "$retention days"}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [1, 3, 7, 30, 0].map((d) {
                    final labels = {1: '1 day', 3: '3 days', 7: '7 days', 30: '30 days', 0: 'Disabled'};
                    return ChoiceChip(
                      label: Text(labels[d]!),
                      selected: retention == d,
                      onSelected: (_) {
                        ref.read(retentionProvider.notifier).state = d;
                        storage.setRetentionDays(d);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ThemeSectionHeader(title: 'Appearance', actionLabel: ''),
        const SizedBox(height: 8),
        ThemeCard(
          child: SwitchListTile(
            title: const Text('Dark mode'),
            subtitle: const Text('Toggle dark theme on or off'),
            value: darkMode,
            onChanged: (v) {
              ref.read(darkModeProvider.notifier).state = v;
              storage.setDarkMode(v);
            },
          ),
        ),
        const SizedBox(height: 20),
        ThemeSectionHeader(title: 'Import / Export', actionLabel: ''),
        const SizedBox(height: 8),
        ThemeCard(
          child: Column(
            children: [
              ThemeListTile(
                leading: const Icon(Icons.upload),
                title: 'Export configuration',
                subtitle: 'Save rules and settings as JSON',
                onTap: () => _export(context, ref),
              ),
              const Divider(height: 1),
              ThemeListTile(
                leading: const Icon(Icons.download),
                title: 'Import configuration',
                subtitle: 'Restore from a JSON file',
                onTap: () => _import(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ThemeSectionHeader(title: 'Advanced', actionLabel: ''),
        const SizedBox(height: 8),
        ThemeCard(
          child: Column(
            children: [
              ThemeListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: 'Developer diagnostics',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/dev'),
              ),
              const Divider(height: 1),
              ThemeListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: 'Clear DNS cache',
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await ref.read(vpnBridgeProvider).clearCache();
                  if (context.mounted) Notify.success(context, 'Cache cleared');
                },
              ),
              const Divider(height: 1),
              ThemeListTile(
                leading: const Icon(Icons.restore),
                title: 'Restore default blocklist',
                subtitle: 'Re-seed built-in ad/tracker/malware/telemetry domains',
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await storage.saveCustomBlocklist(defaultBlocklist);
                  await ref.read(vpnBridgeProvider).syncRules(
                    allowlist: storage.getAllowlist().map((r) => r.toMap()).toList(),
                    blocklist: defaultBlocklist.map((r) => r.toMap()).toList(),
                  );
                  if (context.mounted) Notify.success(context, 'Default blocklist restored (${defaultBlocklist.length} rules)');
                },
              ),
              const Divider(height: 1),
              ThemeListTile(
                leading: const Icon(Icons.info_outline),
                title: 'About',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/about'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final data = await ref.read(storageProvider).exportAll();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/dns_firewall_config.json');
    await file.writeAsString(jsonEncode(data));
    if (context.mounted) {
      await FilePicker.saveFile(
        fileName: 'dns_firewall_config.json',
        bytes: utf8.encode(jsonEncode(data)),
      );
      Notify.success(context, 'Exported to ${file.path}');
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    try {
      final bytes = await result.single.readAsBytes();
      final json = utf8.decode(bytes);
      final data = jsonDecode(json) as Map<String, dynamic>;
      await ref.read(storageProvider).importAll(data);
      if (context.mounted) Notify.success(context, 'Configuration imported');
    } catch (e) {
      if (context.mounted) Notify.error(context, 'Import failed: $e');
    }
  }
}