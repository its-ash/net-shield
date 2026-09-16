import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';

class DnsServersScreen extends ConsumerWidget {
  const DnsServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvers = ref.watch(resolversProvider);
    final activeId = ref.watch(activeResolverProvider);
    return Scaffold(
      appBar: ThemeAppBar(title: 'DNS Resolvers'),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: resolvers.length,
        itemBuilder: (context, i) {
          final r = resolvers[i];
          final isActive = r.id == activeId;
          return ThemeCard(
            selected: isActive,
            child: ThemeListTile(
              leading: Icon(Icons.dns, color: isActive ? Theme.of(context).colorScheme.primary : null),
              title: r.name,
              subtitle: '${r.protocol.toUpperCase()} · ${r.host}:${r.port}',
              trailing: Radio<String>(
                value: r.id,
                groupValue: activeId,
                onChanged: (v) {
                  if (v != null) {
                    ref.read(activeResolverProvider.notifier).state = v;
                    ref.read(storageProvider).setActiveResolverId(v);
                  }
                },
              ),
              onTap: () {
                ref.read(activeResolverProvider.notifier).state = r.id;
                ref.read(storageProvider).setActiveResolverId(r.id);
              },
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
    final nameCtrl = TextEditingController();
    final hostCtrl = TextEditingController(text: '1.1.1.1');
    final portCtrl = TextEditingController(text: '53');
    var protocol = 'udp';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Add DNS resolver'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ThemeTextField(controller: nameCtrl, labelText: 'Name', hintText: 'Cloudflare'),
              ThemeTextField(controller: hostCtrl, labelText: 'Hostname / IP'),
              ThemeTextField(controller: portCtrl, labelText: 'Port'),
              DropdownButtonFormField<String>(
                value: protocol,
                decoration: const InputDecoration(labelText: 'Protocol'),
                items: const [
                  DropdownMenuItem(value: 'udp', child: Text('UDP')),
                  DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                  DropdownMenuItem(value: 'dot', child: Text('DNS-over-TLS (future)')),
                  DropdownMenuItem(value: 'doh', child: Text('DNS-over-HTTPS (future)')),
                ],
                onChanged: (v) => setState(() => protocol = v ?? 'udp'),
              ),
            ],
          ),
          actions: [
            ThemeButton(label: 'Cancel', variant: ThemeButtonVariant.text, onPressed: () => Navigator.pop(ctx)),
            ThemeButton(
              label: 'Add',
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  ref.read(resolversProvider.notifier).add(DnsResolverConfig(
                    id: name.toLowerCase().replaceAll(' ', '_'),
                    name: name,
                    protocol: protocol,
                    host: hostCtrl.text.trim(),
                    port: int.tryParse(portCtrl.text.trim()) ?? 53,
                  ));
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