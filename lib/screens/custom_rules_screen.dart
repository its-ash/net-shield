import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';

class CustomRulesScreen extends ConsumerWidget {
  const CustomRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(customBlocklistProvider);
    return Scaffold(
      appBar: ThemeAppBar(title: 'Custom Blocklist'),
      body: list.isEmpty
          ? ThemeEmptyState(
              icon: Icons.rule,
              title: 'No custom rules',
              subtitle: 'Add domains to block manually.',
            )
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final e = list[i];
                return ThemeListTile(
                  leading: const Icon(Icons.block, color: Colors.red),
                  title: e.domain,
                  subtitle: '${e.category.name} · ${e.exact ? "exact" : "suffix"}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: e.enabled,
                        onChanged: (_) => ref.read(customBlocklistProvider.notifier).toggleEnabled(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref.read(customBlocklistProvider.notifier).removeAt(i),
                      ),
                    ],
                  ),
                  onTap: () => _showEditDialog(context, ref, i, e),
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
    var category = RuleCategory.custom;
    var exact = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add custom block rule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ThemeTextField(controller: domainCtrl, labelText: 'Domain', hintText: 'ads.example.com'),
              DropdownButtonFormField<RuleCategory>(
                value: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: RuleCategory.values
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => category = v ?? RuleCategory.custom),
              ),
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
                  ref.read(customBlocklistProvider.notifier).add(RuleEntry(domain: d, category: category, exact: exact));
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, int index, RuleEntry entry) {
    final domainCtrl = TextEditingController(text: entry.domain);
    var category = entry.category;
    var exact = entry.exact;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Edit rule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ThemeTextField(controller: domainCtrl, labelText: 'Domain'),
              DropdownButtonFormField<RuleCategory>(
                value: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: RuleCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                onChanged: (v) => setState(() => category = v ?? RuleCategory.custom),
              ),
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
              label: 'Save',
              onPressed: () {
                ref.read(customBlocklistProvider.notifier).update(index, RuleEntry(
                  domain: domainCtrl.text.trim().toLowerCase(),
                  category: category,
                  exact: exact,
                  enabled: entry.enabled,
                ));
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}