import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_profile.dart';
import '../../models/browser_tab.dart';
import '../../services/tab_service.dart';
import '../../services/thumbnail_cache.dart';
import 'site_style.dart';
import 'url_utils.dart';

/// Chrome-style tab switcher: big + button, grid or list switch, tab search,
/// and page pictures. Pops [switchProfile] when the user wants to change profile.
class TabSwitcherScreen extends StatefulWidget {
  const TabSwitcherScreen({super.key, required this.tabs, required this.profile});
  final TabService tabs;
  final AppProfile profile;

  /// Popped as the result when "Switch profile" is chosen.
  static const String switchProfile = 'switch_profile';

  @override
  State<TabSwitcherScreen> createState() => _TabSwitcherScreenState();
}

class _TabSwitcherScreenState extends State<TabSwitcherScreen> {
  bool _grid = true;
  final TextEditingController _q = TextEditingController();

  TabService get _tabs => widget.tabs;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _isStart(BrowserTab t) => t.url.isEmpty || t.url == kHomeUrl;

  String _title(BrowserTab t) {
    if (_isStart(t)) return 'New tab';
    if (t.title.isNotEmpty) return t.title;
    final host = Uri.tryParse(t.url)?.host ?? '';
    return host.isNotEmpty ? host : 'New tab';
  }

  Future<void> _select(BrowserTab t) async {
    await _tabs.select(t.id);
    if (mounted) Navigator.pop(context);
  }

  void _closeTab(BrowserTab t) {
    ThumbnailCache.remove(t.id);
    _tabs.close(t.id);
  }

  Future<void> _newTab() async {
    await _tabs.addTab(url: _tabs.homeUrl, desktop: _tabs.desktopDefault);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _closeAll() async {
    ThumbnailCache.clear();
    await _tabs.closeAll();
    if (mounted) Navigator.pop(context);
  }

  Widget _countBox(BuildContext context, int n) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 1.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _segment(BuildContext context, {required bool selected, required VoidCallback onTap, required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 54,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      ),
    );
  }

  Widget _topBar(BuildContext context, int count) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
      child: Row(
        children: [
          Material(
            color: cs.primary,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _newTab,
              child: SizedBox(
                width: 54,
                height: 54,
                child: Icon(Icons.add, size: 30, color: cs.onPrimary),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: context.panel, borderRadius: BorderRadius.circular(26)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _segment(context, selected: _grid, onTap: () => setState(() => _grid = true), child: _countBox(context, count)),
                    _segment(context, selected: !_grid, onTap: () => setState(() => _grid = false), child: const Icon(Icons.view_list_outlined, size: 22)),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'profile') Navigator.pop(context, TabSwitcherScreen.switchProfile);
              if (v == 'closeall') _closeAll();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'profile', child: Text('Switch profile (${widget.profile.displayName})')),
              const PopupMenuItem(value: 'closeall', child: Text('Close all tabs')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gridCard(BuildContext context, BrowserTab t) {
    final cs = Theme.of(context).colorScheme;
    final active = t.id == _tabs.activeId;
    final title = _title(t);
    final start = _isStart(t);
    final thumb = ThumbnailCache.get(t.id);
    final host = Uri.tryParse(t.url)?.host ?? '';
    return Material(
      color: active ? cs.primaryContainer : context.panel,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _select(t),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 2, 10),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: start ? context.faint : siteColor(t.url, title),
                    child: Text(
                      title.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close tab',
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    onPressed: () => _closeTab(t),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox.expand(
                      child: thumb != null
                          ? Image.memory(thumb, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true)
                          : Container(
                              color: context.faint,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(start ? Icons.home_outlined : Icons.public, size: 34, color: context.muted),
                                  const SizedBox(height: 4),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    child: Text(
                                      start ? 'Start page' : host,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: context.muted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listRow(BuildContext context, BrowserTab t, {required int index, required bool drag}) {
    final active = t.id == _tabs.activeId;
    final title = _title(t);
    return Padding(
      key: ValueKey(t.id),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: context.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: active ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _select(t),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _isStart(t) ? context.faint : siteColor(t.url, title),
                  child: Text(title.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        _isStart(t) ? 'Start page' : t.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: context.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(tooltip: 'Close tab', icon: const Icon(Icons.close), onPressed: () => _closeTab(t)),
                if (drag)
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                      child: Icon(Icons.drag_handle, color: context.muted),
                    ),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _tabs,
      builder: (context, _) {
        final all = _tabs.tabs;
        final q = _q.text.trim().toLowerCase();
        final shown = q.isEmpty
            ? all
            : all.where((t) => _title(t).toLowerCase().contains(q) || t.url.toLowerCase().contains(q)).toList();
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _topBar(context, all.length),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _q,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search your tabs',
                      isDense: true,
                      filled: true,
                      fillColor: context.panel,
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const Center(child: Text('No tabs match your search'))
                      : _grid
                          ? GridView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.78,
                              ),
                              itemCount: shown.length,
                              itemBuilder: (_, i) => _gridCard(context, shown[i]),
                            )
                          : (q.isEmpty
                              ? ReorderableListView.builder(
                                  buildDefaultDragHandles: false,
                                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                                  itemCount: shown.length,
                                  onReorder: (o, n) => _tabs.move(o, n),
                                  itemBuilder: (_, i) => _listRow(context, shown[i], index: i, drag: true),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                                  itemCount: shown.length,
                                  itemBuilder: (_, i) => _listRow(context, shown[i], index: i, drag: false),
                                )),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
