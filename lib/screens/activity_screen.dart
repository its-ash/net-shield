import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:theme/theme.dart';
import '../models/models.dart';
import '../providers/providers.dart';

enum LogFilter { all, blocked, allowed }

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  LogFilter _filter = LogFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = ref.watch(liveLogProvider.stream);
    final timeFmt = DateFormat.Hms();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: ThemeSearchBar(
            controller: _searchController,
            hintText: 'Search domains…',
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              FilterChip(label: const Text('All'), selected: _filter == LogFilter.all, onSelected: (_) => setState(() => _filter = LogFilter.all)),
              const SizedBox(width: 8),
              FilterChip(label: const Text('Blocked'), selected: _filter == LogFilter.blocked, onSelected: (_) => setState(() => _filter = LogFilter.blocked)),
              const SizedBox(width: 8),
              FilterChip(label: const Text('Allowed'), selected: _filter == LogFilter.allowed, onSelected: (_) => setState(() => _filter = LogFilter.allowed)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Clear'),
                onPressed: () async {
                  await ref.read(storageProvider).clearLogs();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _LogListView(
            stream: stream,
            filter: _filter,
            search: _search,
            timeFmt: timeFmt,
          ),
        ),
      ],
    );
  }
}

class _LogListView extends StatefulWidget {
  final Stream<QueryLogEntry> stream;
  final LogFilter filter;
  final String search;
  final DateFormat timeFmt;

  const _LogListView({
    required this.stream,
    required this.filter,
    required this.search,
    required this.timeFmt,
  });

  @override
  State<_LogListView> createState() => _LogListViewState();
}

class _LogListViewState extends State<_LogListView> {
  final List<QueryLogEntry> _items = [];
  static const _max = 1000;

  @override
  void initState() {
    super.initState();
    widget.stream.listen((e) {
      if (!mounted) return;
      setState(() {
        _items.insert(0, e);
        if (_items.length > _max) _items.removeLast();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    var items = _items;
    if (widget.filter == LogFilter.blocked) items = items.where((e) => e.action == QueryAction.blocked).toList();
    if (widget.filter == LogFilter.allowed) items = items.where((e) => e.action == QueryAction.allowed).toList();
    if (widget.search.isNotEmpty) {
      items = items.where((e) => e.domain.toLowerCase().contains(widget.search)).toList();
    }

    if (items.isEmpty) {
      return ThemeEmptyState(
        icon: Icons.list_alt,
        title: 'No matching queries',
        subtitle: 'DNS queries will appear here in real-time when protection is active.',
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final e = items[i];
        final blocked = e.action == QueryAction.blocked;
        return ThemeListTile(
          leading: Icon(
            blocked ? Icons.block : Icons.check_circle_outline,
            color: blocked ? Theme.of(context).colorScheme.error : Colors.green,
            size: 20,
          ),
          title: e.domain,
          subtitle: '${widget.timeFmt.format(e.timestamp)} · ${e.sourceApp ?? '—'} · ${e.category?.name ?? ''}',
          trailing: ThemeStatusPill(
            label: blocked ? 'BLOCKED' : 'ALLOWED',
            status: blocked ? ThemeStatus.error : ThemeStatus.success,
          ),
        );
      },
    );
  }
}