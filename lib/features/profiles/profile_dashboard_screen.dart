import '../extensions/extensions_tab.dart';
import '../home/home_stats_strip.dart';
import '../home/popular_tab.dart';
import '../home/shortcut_dialog.dart';
import '../settings/settings_screen.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_profile.dart';
import '../../models/home_shortcut.dart';
import '../../services/extension_service.dart';
import '../../services/home_service.dart';
import '../../services/profile_service.dart';
import '../browser/browser_screen.dart';
import 'profile_dialogs.dart';
import 'profile_style.dart';

enum _Sort { number, name, lastActive }

class ProfileDashboardScreen extends StatefulWidget {
  const ProfileDashboardScreen({super.key, required this.service});
  final ProfileService service;

  @override
  State<ProfileDashboardScreen> createState() => _ProfileDashboardScreenState();
}

class _ProfileDashboardScreenState extends State<ProfileDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtl = TabController(length: 3, vsync: this);
  late final ExtensionService _ext = ExtensionService(widget.service.db);
  late final HomeService _home = HomeService(widget.service.db);
  HomeStats? _stats;
  final Set<String> _selected = {};
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  bool _busy = false;
  _Sort _sort = _Sort.number;

  ProfileService get _s => widget.service;
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _tabCtl.addListener(() {
      if (!_tabCtl.indexIsChanging && mounted) setState(() {});
    });
    _home.addListener(_refreshStats);
    _s.addListener(_refreshStats);
    _ext.addListener(_refreshStats);
    _home.load();
    _ext.load();
    _refreshStats();
  }

  @override
  void dispose() {
    _home.removeListener(_refreshStats);
    _ext.removeListener(_refreshStats);
    _ext.dispose();
    _s.removeListener(_refreshStats);
    _home.dispose();
    _tabCtl.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refreshStats() async {
    final st = await _home.stats();
    if (mounted) setState(() => _stats = st);
  }

  Future<void> _addExtension() => showAddExtensionFlow(context, _ext);

  Future<void> _addSite() async {
    final r = await showShortcutDialog(context);
    if (r == null) return;
    final added = await _home.add(url: r.url, title: r.title, pinned: r.pinned, image: r.image);
    _toast(added ? 'Added to Popular' : 'That site is already in Popular');
  }

  /// Asks which profile should open a Popular site.
  Future<void> _openShortcut(HomeShortcut s) async {
    final list = [..._s.profiles]..sort((a, b) => a.number.compareTo(b.number));
    if (list.isEmpty) {
      _toast('Create a profile first');
      return;
    }
    if (!_s.supported) {
      _toast('Profiles are not supported on this device');
      return;
    }
    AppProfile? chosen;
    if (list.length == 1) {
      chosen = list.first;
    } else {
      chosen = await showModalBottomSheet<AppProfile>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Open ${s.title} in which profile?',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in list)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: ProfileStyle.colorFor(p.color),
                            child: Icon(ProfileStyle.iconFor(p.icon), color: Colors.white, size: 20),
                          ),
                          title: Text(p.displayName),
                          subtitle: Text(ProfileStyle.lastActiveShort(p.lastActiveAt)),
                          onTap: () => Navigator.pop(ctx, p),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (chosen != null && mounted) await _open(chosen, initialUrl: s.url);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  List<AppProfile> _visible() {
    final q = _search.text.trim().toLowerCase();
    final list = _s.profiles
        .where((p) => q.isEmpty || p.displayName.toLowerCase().contains(q))
        .toList();
    switch (_sort) {
      case _Sort.number:
        list.sort((a, b) => a.number.compareTo(b.number));
      case _Sort.name:
        list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      case _Sort.lastActive:
        list.sort((a, b) => (b.lastActiveAt ?? 0).compareTo(a.lastActiveAt ?? 0));
    }
    return list;
  }

  Future<void> _create() async {
    final qty = await showCreateProfilesDialog(context);
    if (qty == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await _s.createProfiles(qty);
      if (r.failed.isEmpty) {
        _toast(r.created == 1 ? 'Profile created' : '${r.created} profiles created');
      } else {
        _toast('${r.created} created, ${r.failed.length} failed (${r.failed.join(", ")}). Try again to fill the gap.');
      }
    } catch (e) {
      _toast('Could not create profiles: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(AppProfile p, {String? initialUrl}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowserScreen(profile: p, service: _s, initialUrl: initialUrl),
      ),
    );
    _refreshStats();
  }

  Future<void> _rename(AppProfile p) async {
    final name = await showRenameDialog(context, p.displayName);
    if (name == null) return;
    try {
      await _s.rename(p.id, name);
    } catch (e) {
      _toast('Could not rename: $e');
    }
  }

  Future<void> _appearance(AppProfile p) async {
    final pick = await showAppearanceDialog(
      context,
      icon: p.icon ?? 'person',
      color: p.color ?? '#7351FF',
    );
    if (pick == null) return;
    await _s.setStyle(p.id, icon: pick.icon, color: pick.color);
  }

  Future<void> _delete(List<AppProfile> targets) async {
    if (targets.isEmpty) return;
    final ok = await confirmDelete(context, targets.length, targets.first.displayName);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await _s.deleteProfiles(targets.map((e) => e.id).toList());
      _selected.clear();
      if (r.failed.isEmpty) {
        _toast(r.deleted == 1 ? 'Profile deleted' : '${r.deleted} profiles deleted');
      } else {
        _toast('${r.deleted} deleted, ${r.failed.length} could not be deleted. They stay in the list.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _openSettings() {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  PreferredSizeWidget _appBar() {
    if (_selecting) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(_selected.clear),
        ),
        title: Text('${_selected.length} selected'),
        actions: [
          IconButton(
            tooltip: 'Select all',
            icon: const Icon(Icons.select_all),
            onPressed: () => setState(() => _selected.addAll(_visible().map((e) => e.id))),
          ),
          IconButton(
            tooltip: 'Delete selected',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(_s.profiles.where((p) => _selected.contains(p.id)).toList()),
          ),
        ],
      );
    }
    return AppBar(
      title: _searching
          ? TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Search profiles', border: InputBorder.none),
              onChanged: (_) => setState(() {}),
            )
          : const Text('K-Multi Browser'),
      actions: [
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: _openSettings,
        ),
        IconButton(
          tooltip: 'Search',
          icon: Icon(_searching ? Icons.close : Icons.search),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) _search.clear();
          }),
        ),
        PopupMenuButton<_Sort>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: _Sort.number, child: Text('By number')),
            PopupMenuItem(value: _Sort.name, child: Text('By name')),
            PopupMenuItem(value: _Sort.lastActive, child: Text('By last active')),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final items = _visible();
        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(_selected.clear);
          },
          child: Scaffold(
            appBar: _appBar(),
            floatingActionButton: _tabCtl.index == 2
                ? FloatingActionButton.extended(
                    onPressed: _addExtension,
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.darkBase,
                    icon: const Icon(Icons.add),
                    label: const Text('Add extension'),
                  )
                : _tabCtl.index == 1
                ? FloatingActionButton.extended(
                    onPressed: _addSite,
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.darkBase,
                    icon: const Icon(Icons.add),
                    label: const Text('Add site'),
                  )
                : (_s.supported && !_selecting
                    ? FloatingActionButton.extended(
                        onPressed: _busy ? null : _create,
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.darkBase,
                        icon: const Icon(Icons.add),
                        label: const Text('Create Profiles'),
                      )
                    : null),
            body: Column(
              children: [
                if (_busy) const LinearProgressIndicator(minHeight: 3),
                if (!_s.supported)
                  Container(
                    width: double.infinity,
                    color: Colors.red.withValues(alpha: 0.25),
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'This device\'s WebView (${_s.engineInfo}) does not support multiple profiles. '
                      'Update Android System WebView or Chrome. Profiles are disabled; shared storage is never used as a fallback.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                HomeStatsStrip(stats: _stats, profiles: _s.profiles),
                TabBar(
                  controller: _tabCtl,
                  tabs: [
                    Tab(text: 'Profiles (${_s.profiles.length})'),
                    Tab(text: 'Popular (${_stats?.shortcuts ?? 0})'),
                    Tab(text: 'Extensions (${_stats?.extensions ?? 0})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtl,
                    children: [
                      _profilesView(items),
                      PopularTab(home: _home, onOpen: _openShortcut, onToast: _toast),
                      ExtensionsTab(service: _ext),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _profilesView(List<AppProfile> items) {
    return items.isEmpty
        ? Center(
            child: Text(
              _s.profiles.isEmpty ? 'No profiles yet. Tap Create Profiles.' : 'No profile matches your search.',
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _card(items[i]),
          );
  }

  Widget _card(AppProfile p) {
    final color = ProfileStyle.colorFor(p.color);
    final selected = _selected.contains(p.id);
    return Material(
      color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25) : context.panel,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selecting ? _toggle(p.id) : _open(p),
        onLongPress: () => _toggle(p.id),
        child: Stack(
          children: [
            Positioned(top: 0, left: 0, right: 0, child: Container(height: 4, color: color)),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: color,
                    child: Icon(ProfileStyle.iconFor(p.icon), color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    p.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ProfileStyle.lastActiveShort(p.lastActiveAt),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: context.muted),
                  ),
                ],
              ),
            ),
            if (_selecting)
              Positioned(
                top: 10,
                left: 8,
                child: Icon(selected ? Icons.check_circle : Icons.circle_outlined, size: 20),
              )
            else
              Positioned(
                top: 4,
                right: 0,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  onSelected: (v) {
                    switch (v) {
                      case 'open':
                        _open(p);
                      case 'rename':
                        _rename(p);
                      case 'look':
                        _appearance(p);
                      case 'delete':
                        _delete([p]);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'open', child: Text('Open')),
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'look', child: Text('Colour and icon')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
