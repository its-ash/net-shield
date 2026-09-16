import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';

class AppsScreen extends ConsumerWidget {
  const AppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(appRulesProvider);
    return Scaffold(
      appBar: ThemeAppBar(title: 'App Rules'),
      body: Column(
        children: [
          ThemeCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Per-app VPN routing lets you set individual apps as Protected (DNS filtered) or Bypass (skip the firewall). '
                'Android VPN routing is all-or-nothing per app — bypassed apps use the underlying network directly. '
                'Attribution of DNS queries to apps is only available where the Android VPN API reliably provides it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: rules.isEmpty
                ? ThemeEmptyState(
                    icon: Icons.apps,
                    title: 'No app rules',
                    subtitle: 'Add an app rule to configure per-app bypass.',
                  )
                : ListView.builder(
                    itemCount: rules.length,
                    itemBuilder: (context, i) {
                      final r = rules[i];
                      return ThemeListTile(
                        leading: const Icon(Icons.android),
                        title: r.appName,
                        subtitle: r.packageName,
                        trailing: DropdownButton<bool>(
                          value: r.bypass,
                          items: const [
                            DropdownMenuItem(value: false, child: Text('Protected')),
                            DropdownMenuItem(value: true, child: Text('Bypass')),
                          ],
                          onChanged: (v) => ref.read(appRulesProvider.notifier).update(i, AppRule(
                            packageName: r.packageName,
                            appName: r.appName,
                            bypass: v ?? false,
                          )),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final pkgCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add app rule'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThemeTextField(controller: nameCtrl, labelText: 'App name', hintText: 'Chrome'),
            ThemeTextField(controller: pkgCtrl, labelText: 'Package name', hintText: 'com.android.chrome'),
          ],
        ),
        actions: [
          ThemeButton(label: 'Cancel', variant: ThemeButtonVariant.text, onPressed: () => Navigator.pop(ctx)),
          ThemeButton(
            label: 'Add',
            onPressed: () {
              final pkg = pkgCtrl.text.trim();
              final name = nameCtrl.text.trim();
              if (pkg.isNotEmpty) {
                ref.read(appRulesProvider.notifier).add(AppRule(packageName: pkg, appName: name));
              }
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}