import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:theme/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';

class BlocklistsScreen extends ConsumerWidget {
  const BlocklistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(blocklistSourcesProvider);
    return Scaffold(
      appBar: ThemeAppBar(title: 'Blocklist Sources'),
      body: sources.isEmpty
          ? ThemeEmptyState(
              icon: Icons.list,
              title: 'No blocklist sources',
              subtitle: 'Import a local blocklist file to get started. Remote sources can be added later.',
            )
          : ListView.builder(
              itemCount: sources.length,
              itemBuilder: (context, i) {
                final s = sources[i];
                return ThemeListTile(
                  leading: const Icon(Icons.list_alt),
                  title: s.name,
                  subtitle: '${s.ruleCount} rules · ${s.enabled ? "enabled" : "disabled"} · ${s.updateStatus}',
                  trailing: Switch(
                    value: s.enabled,
                    onChanged: (_) => ref.read(blocklistSourcesProvider.notifier).toggleEnabled(i),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _importFile(context, ref),
        child: const Icon(Icons.file_upload_outlined),
      ),
    );
  }

  Future<void> _importFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    final path = result.single.path;
    if (path == null) return;
    final name = result.single.name;
    final lines = await _parseFile(path);
    final source = BlocklistSource(
      id: const Uuid().v4(),
      name: name,
      localPath: path,
      ruleCount: lines,
      lastUpdated: DateTime.now(),
      enabled: true,
      updateStatus: 'imported',
    );
    ref.read(blocklistSourcesProvider.notifier).add(source);
  }

  Future<int> _parseFile(String path) async {
    try {
      final lines = await File(path).readAsLines();
      return lines.where((l) {
        final t = l.trim();
        return t.isNotEmpty && !t.startsWith('#') && !t.startsWith('!');
      }).length;
    } catch (_) {
      return 0;
    }
  }
}