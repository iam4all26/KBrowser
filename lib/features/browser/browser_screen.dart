import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmulti_profiles/kmulti_profiles.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_profile.dart';
import '../../services/profile_service.dart';
import '../../services/tab_service.dart';
import '../profiles/profile_style.dart';
import 'tab_switcher_screen.dart';
import 'url_utils.dart';

const String _testBase = 'https://kmulti.test/';

/// Browser for ONE profile. Every tab is a WebView bound to this profile.
/// Only tabs that were opened in this session have a live WebView; restored
/// background tabs get theirs when you switch to them (saves memory).
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.profile, required this.service});
  final AppProfile profile;
  final ProfileService service;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final TabService _tabs = TabService(widget.service.db, widget.profile.id);
  final Map<String, KWebViewController> _ctl = {};
  final Set<String> _live = {};
  final TextEditingController _url = TextEditingController();
  final FocusNode _focus = FocusNode();
  SearchEngine _engine = SearchEngines.google;
  bool _ready = false;
  String? _error;

  AppProfile get _p => widget.profile;
  KWebViewController? get _activeCtl {
    final id = _tabs.activeId;
    return id == null ? null : _ctl[id];
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _init();
  }

  Future<void> _init() async {
    try {
      _engine = SearchEngines.byId(await widget.service.getSetting(_p.id, 'search_engine'));
      _tabs.homeUrl = _engine.homeUrl;
      _tabs.desktopDefault = _p.desktopMode;
      await _tabs.load();
      _tabs.addListener(_onTabsChanged);
      _syncLive();
      widget.service.touchActive(_p.id);
      if (!mounted) return;
      setState(() => _ready = true);
      _syncUrlText();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabsChanged);
    _tabs.dispose();
    _focus.dispose();
    _url.dispose();
    super.dispose();
  }

  void _syncLive() {
    final ids = _tabs.tabs.map((t) => t.id).toSet();
    _live.removeWhere((id) => !ids.contains(id));
    _ctl.removeWhere((id, _) => !ids.contains(id));
    final a = _tabs.activeId;
    if (a != null) _live.add(a);
  }

  void _onTabsChanged() {
    if (!mounted) return;
    _syncLive();
    _syncUrlText();
    setState(() {});
  }

  void _syncUrlText() {
    if (_focus.hasFocus) return;
    final t = _tabs.active;
    _url.text = t?.url ?? '';
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _url.selection = TextSelection(baseOffset: 0, extentOffset: _url.text.length);
    } else {
      _syncUrlText();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _attach(String tabId, KWebViewController c) {
    _ctl[tabId] = c;
    c.onNewWindow = (u) {
      _tabs.addTab(url: u, desktop: _p.desktopMode);
    };
    c.onDownloadMessage = _toast;
    c.state.addListener(() {
      if (!mounted) return;
      final s = c.state.value;
      if (s.url.isNotEmpty) _tabs.updatePage(tabId, s.url, s.title);
      setState(() {});
    });
    c.progress.addListener(() {
      if (mounted && tabId == _tabs.activeId) setState(() {});
    });
    for (final t in _tabs.tabs) {
      if (t.id != tabId) continue;
      if (t.desktopMode) c.setDesktopMode(true, reload: false);
      if (t.url.startsWith(_testBase)) {
        c.loadTestPage();
      } else {
        c.loadUrl(t.url.isEmpty ? _engine.homeUrl : t.url);
      }
      break;
    }
    setState(() {});
  }

  void _go() {
    final u = resolveInput(_url.text, _engine);
    _focus.unfocus();
    final id = _tabs.activeId;
    if (id == null) return;
    final c = _ctl[id];
    if (c != null) {
      c.loadUrl(u);
    } else {
      _tabs.updatePage(id, u, '');
    }
  }

  Future<void> _newTab() => _tabs.addTab(url: _engine.homeUrl, desktop: _p.desktopMode);

  Future<void> _toggleDesktop() async {
    final t = _tabs.active;
    if (t == null) return;
    final next = !t.desktopMode;
    await _tabs.setDesktop(t.id, next);
    _ctl[t.id]?.setDesktopMode(next);
  }

  Future<void> _openSwitcher() async {
    _focus.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TabSwitcherScreen(tabs: _tabs)),
    );
  }

  Future<void> _pickEngine() async {
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Search engine'),
        children: [
          for (final e in SearchEngines.all)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.id),
              child: Row(
                children: [
                  Icon(e.id == _engine.id ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
                  const SizedBox(width: 12),
                  Text(e.name),
                ],
              ),
            ),
        ],
      ),
    );
    if (id == null) return;
    await widget.service.setSetting(_p.id, 'search_engine', id);
    if (!mounted) return;
    setState(() {
      _engine = SearchEngines.byId(id);
      _tabs.homeUrl = _engine.homeUrl;
    });
  }

  void _openMenu() {
    _focus.unfocus();
    final t = _tabs.active;
    final url = t?.url ?? '';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap, {Widget? trailing}) {
          return ListTile(
            leading: Icon(icon),
            title: Text(label),
            trailing: trailing,
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                item(Icons.add, 'New Tab', _newTab),
                if (_tabs.recentlyClosed.isNotEmpty)
                  item(Icons.undo, 'Reopen closed tab', () => _tabs.reopenClosed()),
                if (t != null) item(Icons.copy_all_outlined, 'Duplicate tab', () => _tabs.duplicate(t.id)),
                item(
                  Icons.desktop_windows_outlined,
                  'Request Desktop Site',
                  _toggleDesktop,
                  trailing: IgnorePointer(
                    child: Switch(value: t?.desktopMode ?? false, onChanged: (_) {}),
                  ),
                ),
                if (url.startsWith('http')) ...[
                  item(Icons.link, 'Copy link', () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    _toast('Link copied');
                  }),
                  item(Icons.share_outlined, 'Share link', () async {
                    try {
                      await KMultiProfiles.share(url);
                    } catch (e) {
                      _toast('Could not share: $e');
                    }
                  }),
                ],
                item(Icons.download_outlined, 'Downloads', () async {
                  try {
                    await KMultiProfiles.openDownloads();
                  } catch (e) {
                    _toast('Could not open Downloads: $e');
                  }
                }),
                item(Icons.search, 'Search engine: ${_engine.name}', _pickEngine),
                item(Icons.science_outlined, 'Isolation test page', () => _activeCtl?.loadTestPage()),
                item(Icons.cookie_outlined, 'Show cookies for this page', _showCookies),
                item(Icons.delete_sweep_outlined, 'Close all tabs', () => _tabs.closeAll()),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCookies() async {
    final url = _tabs.active?.url ?? '';
    var text = '(no web page loaded yet)';
    if (url.startsWith('http')) {
      try {
        text = await KMultiProfiles.cookies(_p.engineProfileName, url) ?? '(none)';
      } catch (e) {
        text = 'error: $e';
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cookies: ${_p.displayName}'),
        content: SingleChildScrollView(child: SelectableText('$url\n\n$text')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Widget _tabView(String id) {
    return KeyedSubtree(
      key: ValueKey(id),
      child: _live.contains(id)
          ? KProfileWebView(
              key: ValueKey('wv_$id'),
              profile: _p.engineProfileName,
              onCreated: (c) => _attach(id, c),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_p.displayName)),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not open: $_error'))),
      );
    }
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: Text(_p.displayName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final color = ProfileStyle.colorFor(_p.color);
    final active = _tabs.active;
    final activeIndex = _tabs.tabs.indexWhere((t) => t.id == _tabs.activeId);
    final c = _activeCtl;
    final progress = c?.progress.value ?? 1.0;
    final loading = progress < 1.0;
    final canBack = c?.state.value.canGoBack ?? false;
    final canForward = c?.state.value.canGoForward ?? false;
    final secure = (active?.url ?? '').startsWith('https://');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_focus.hasFocus) {
          _focus.unfocus();
        } else if (canBack) {
          c?.goBack();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: color,
                    child: Icon(ProfileStyle.iconFor(_p.icon), size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(_p.displayName, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: loading ? 'Stop' : 'Reload',
              icon: Icon(loading ? Icons.close : Icons.refresh),
              onPressed: () => loading ? c?.stop() : c?.reload(),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: TextField(
                controller: _url,
                focusNode: _focus,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _go(),
                decoration: InputDecoration(
                  hintText: 'Search or enter address',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(secure ? Icons.lock_outline : Icons.public, size: 18),
                  suffixIcon: IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _url.clear();
                      _focus.requestFocus();
                    },
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 2,
              child: loading ? LinearProgressIndicator(value: progress, minHeight: 2) : null,
            ),
            Expanded(
              child: IndexedStack(
                index: activeIndex < 0 ? 0 : activeIndex,
                children: [for (final t in _tabs.tabs) _tabView(t.id)],
              ),
            ),
            SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: canBack ? () => c?.goBack() : null,
                  ),
                  IconButton(
                    tooltip: 'Forward',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: canForward ? () => c?.goForward() : null,
                  ),
                  IconButton(
                    tooltip: 'Home',
                    icon: const Icon(Icons.home_outlined),
                    onPressed: () => c?.loadUrl(_engine.homeUrl),
                  ),
                  InkResponse(
                    onTap: _openSwitcher,
                    radius: 24,
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 1.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_tabs.tabs.length}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Menu',
                    icon: const Icon(Icons.more_vert),
                    onPressed: _openMenu,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
