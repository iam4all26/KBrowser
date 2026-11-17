import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/bookmark.dart';
import '../../models/history_entry.dart';
import '../../services/bookmark_service.dart';
import '../../services/history_service.dart';
import 'url_utils.dart';
import 'bookmark_dialog.dart';

class _Site {
  const _Site(this.name, this.url);
  final String name;
  final String url;
}

const List<_Site> _popular = [
  _Site('Google', 'https://www.google.com'),
  _Site('YouTube', 'https://www.youtube.com'),
  _Site('Wikipedia', 'https://www.wikipedia.org'),
  _Site('GitHub', 'https://github.com'),
  _Site('DuckDuckGo', 'https://duckduckgo.com'),
  _Site('Bing', 'https://www.bing.com'),
  _Site('Reddit', 'https://www.reddit.com'),
  _Site('News', 'https://news.google.com'),
];

/// Start page of a tab (shown instead of a web page). Search box on top, then
/// three views: Shortcuts, Bookmarks and History of THIS profile only.
class StartPage extends StatefulWidget {
  const StartPage({
    super.key,
    required this.profileName,
    required this.engine,
    required this.history,
    required this.bookmarks,
    required this.onOpen,
    required this.onOpenHistory,
    required this.onAddBookmark,
    this.initialTab = 0,
  });

  final String profileName;
  final SearchEngine engine;
  final HistoryService history;
  final BookmarkService bookmarks;
  final void Function(String url) onOpen;
  final VoidCallback onOpenHistory;
  final Future<void> Function(String url, String title, bool allProfiles) onAddBookmark;
  final int initialTab;

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  final TextEditingController _q = TextEditingController();
  late int _tab = widget.initialTab;
  List<Bookmark> _marks = [];
  List<HistoryEntry> _hist = [];
  List<_Site> _frequent = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final q = _q.text;
    final marks = await widget.bookmarks.list(query: q);
    final hist = await widget.history.list(query: q, limit: 400);
    final counts = <String, int>{};
    final urls = <String, String>{};
    for (final h in hist) {
      final u = Uri.tryParse(h.url);
      if (u == null || u.host.isEmpty) continue;
      counts[u.host] = (counts[u.host] ?? 0) + 1;
      urls.putIfAbsent(u.host, () => '${u.scheme}://${u.host}');
    }
    final hosts = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    if (!mounted) return;
    setState(() {
      _marks = marks;
      _hist = hist;
      _frequent = [for (final h in hosts.take(8)) _Site(h.replaceFirst('www.', ''), urls[h]!)];
    });
  }

  Widget _addBookmarkButton() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add bookmark'),
          onPressed: _addDialog,
        ),
      );

  Future<void> _addDialog() async {
    final r = await showBookmarkDialog(context, url: '', title: '', editableUrl: true);
    if (r == null) return;
    await widget.onAddBookmark(r.url, r.title, r.allProfiles);
    if (mounted) _load();
  }

  void _submit(String text) {
    if (text.trim().isEmpty) return;
    widget.onOpen(resolveInput(text, widget.engine));
  }

  String _label(String title, String url) {
    if (title.isNotEmpty) return title;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isNotEmpty ? host : url;
  }

  Widget _avatar(String name) {
    final c = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      child: Text(c),
    );
  }

  Widget _tiles(List<_Site> sites) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.95,
      children: [
        for (final s in sites)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onOpen(s.url),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: context.panel,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    child: Text(s.name.characters.first.toUpperCase(),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
        child: Text(t, style: TextStyle(fontSize: 13, color: context.muted, fontWeight: FontWeight.w600)),
      );

  List<Widget> _body() {
    final filtering = _q.text.trim().isNotEmpty;
    switch (_tab) {
      case 1:
        if (_marks.isEmpty) {
          return [
            _addBookmarkButton(),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                filtering
                    ? 'No bookmarks match.'
                    : 'No bookmarks yet. Open a page, then Menu > Add to bookmarks.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted),
              ),
            ),
          ];
        }
        return [
          _addBookmarkButton(),
          for (final b in _marks)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: _avatar(_label(b.title, b.url)),
              title: Text(_label(b.title, b.url), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(b.url, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Remove bookmark',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () async {
                  await widget.bookmarks.delete(b.id);
                  _load();
                },
              ),
              onTap: () => widget.onOpen(b.url),
            ),
        ];
      case 2:
        final list = _hist.take(60).toList();
        if (list.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                filtering ? 'No history matches.' : 'No history yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted),
              ),
            ),
          ];
        }
        return [
          for (final h in list)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: _avatar(_label(h.title, h.url)),
              title: Text(_label(h.title, h.url), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(h.url, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => widget.onOpen(h.url),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('Open full history'),
              onPressed: widget.onOpenHistory,
            ),
          ),
        ];
      default:
        final pop = filtering
            ? _popular.where((s) => s.name.toLowerCase().contains(_q.text.trim().toLowerCase())).toList()
            : _popular;
        return [
          if (pop.isNotEmpty) ...[_sectionTitle('Popular'), _tiles(pop)],
          if (_frequent.isNotEmpty) ...[_sectionTitle('Frequently visited'), _tiles(_frequent)],
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Text('K-Multi Browser', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(widget.profileName, style: TextStyle(color: context.muted)),
          const SizedBox(height: 16),
          TextField(
            controller: _q,
            textInputAction: TextInputAction.go,
            onChanged: (_) => _load(),
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Search ${widget.engine.name}, type an address, or filter below',
              isDense: true,
              filled: true,
              fillColor: context.panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _q.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Search the web',
                      icon: const Icon(Icons.arrow_forward, size: 20),
                      onPressed: () => _submit(_q.text),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Shortcuts')),
              ButtonSegment(value: 1, label: Text('Bookmarks')),
              ButtonSegment(value: 2, label: Text('History')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) {
              setState(() => _tab = s.first);
            },
          ),
          ..._body(),
        ],
      ),
    );
  }
}
