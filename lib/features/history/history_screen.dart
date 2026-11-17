import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/history_entry.dart';
import '../../services/history_service.dart';

/// History of one profile. Pops with the chosen URL when an entry is tapped.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.history, required this.profileName});
  final HistoryService history;
  final String profileName;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  bool _loading = true;
  List<HistoryEntry> _items = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await widget.history.list(query: _search.text);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history'),
        content: Text('Delete all browsing history of ${widget.profileName}? Other profiles are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.history.clear();
    await _reload();
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  String _title(HistoryEntry e) {
    if (e.title.isNotEmpty) return e.title;
    final host = Uri.tryParse(e.url)?.host ?? '';
    return host.isNotEmpty ? host : e.url;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    String? lastLabel;
    for (final e in _items) {
      final when = DateTime.fromMillisecondsSinceEpoch(e.visitedAt);
      final label = _dayLabel(when);
      if (label != lastLabel) {
        lastLabel = label;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        ));
      }
      final title = _title(e);
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Material(
          color: context.panel,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pop(context, e.url),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: context.faint,
                    child: Text(title.characters.first.toUpperCase()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(e.url, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: context.muted)),
                      ],
                    ),
                  ),
                  Text(_time(when), style: TextStyle(fontSize: 12, color: context.muted)),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () async {
                      await widget.history.delete(e.id);
                      await _reload();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search history', border: InputBorder.none),
                onChanged: (_) => _reload(),
              )
            : Text('History: ${widget.profileName}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) _search.clear();
              });
              if (!_searching) _reload();
            },
          ),
          IconButton(
            tooltip: 'Clear history',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _items.isEmpty && _search.text.isEmpty ? null : _clearAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(_search.text.isEmpty ? 'No history yet.' : 'Nothing matches your search.'))
              : ListView(padding: const EdgeInsets.only(bottom: 24), children: rows),
    );
  }
}
