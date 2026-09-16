import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';

class AllowlistScreen extends ConsumerWidget {
  const AllowlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(allowlistProvider);
    return Scaffold(
      appBar: ThemeAppBar(title: 'Allowlist'),
      body: list.isEmpty
          ? ThemeEmptyState(
              icon: Icons.check_circle_outline,
              title: 'No allowlisted domains',
              subtitle: 'Add domains that should always bypass filtering.',
            )
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final e = list[i];
                return ThemeListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: e.domain,
                  subtitle: e.exact ? 'Exact match' : 'Suffix match',
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ref.read(allowlistProvider.notifier).removeAt(i),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final domainCtrl = TextEditingController();
    var exact = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add to allowlist'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ThemeTextField(controller: domainCtrl, labelText: 'Domain', hintText: 'example.com'),
              CheckboxListTile(
                title: const Text('Exact match only'),
                value: exact,
                onChanged: (v) => setState(() => exact = v ?? false),
              ),
            ],
          ),
          actions: [
            ThemeButton(label: 'Cancel', variant: ThemeButtonVariant.text, onPressed: () => Navigator.pop(ctx)),
            ThemeButton(
              label: 'Add',
              onPressed: () {
                final d = domainCtrl.text.trim().toLowerCase();
                if (d.isNotEmpty) {
                  ref.read(allowlistProvider.notifier).add(RuleEntry(domain: d, exact: exact, category: RuleCategory.custom));
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}