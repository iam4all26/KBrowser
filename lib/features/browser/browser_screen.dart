import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmulti_profiles/kmulti_profiles.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_profile.dart';
import '../../services/profile_service.dart';
import '../../services/bookmark_service.dart';
import '../../services/history_service.dart';
import '../../services/home_service.dart';
import '../../services/download_service.dart';
import '../../services/extension_service.dart';
import '../../services/proxy_service.dart';
import '../../services/tab_service.dart';
import '../../services/thumbnail_cache.dart';
import '../history/history_screen.dart';
import '../profiles/profile_style.dart';
import '../settings/settings_screen.dart';
import '../../models/history_entry.dart';
import '../../services/password_service.dart';
import '../extensions/passwords_script.dart';
import '../passwords/passwords_screen.dart';
import 'bookmark_dialog.dart';
import 'clear_data_dialog.dart';
import 'recent_tabs_sheet.dart';
import 'private_browser_screen.dart';
import 'start_page.dart';
import '../downloads/downloads_screen.dart';
import '../extensions/profile_extensions_screen.dart';
import 'tab_switcher_screen.dart';
import 'top_menu.dart';
import 'url_utils.dart';

const String _testBase = 'https://kmulti.test/';

/// Browser for ONE profile. Every tab is a WebView bound to this profile.
/// Only tabs that were opened in this session have a live WebView; restored
/// background tabs get theirs when you switch to them (saves memory).
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.profile, required this.service, this.initialUrl});
  final AppProfile profile;
  /// If set, this address opens in a new tab as soon as the profile opens.
  final String? initialUrl;
  final ProfileService service;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final TabService _tabs = TabService(widget.service.db, widget.profile.id);
  late final HistoryService _history = HistoryService(widget.service.db, widget.profile.id);
  late final BookmarkService _bookmarks = BookmarkService(widget.service.db, widget.profile.id);
  int _startTab = 0;
  final Map<String, KWebViewController> _ctl = {};
  final Set<String> _live = {};
  final TextEditingController _url = TextEditingController();
  final FocusNode _focus = FocusNode();
  SearchEngine _engine = SearchEngines.google;
  bool _ready = false;
  String? _error;
  bool _finding = false;
  String? _findTabId;
  final TextEditingController _findText = TextEditingController();
  final FocusNode _findFocus = FocusNode();

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

  late final ExtensionService _ext = ExtensionService(widget.service.db);
  late final HomeService _home = HomeService(widget.service.db);
  late final ProxyService _proxy = ProxyService(widget.service.db);
  late final DownloadService _downloads = DownloadService(widget.service.db);
  bool _switching = false; // WebViews are being released before another profile opens
  late final PasswordService _pw = PasswordService(widget.service.db, widget.profile.id);
  bool _pwOn = true;
  bool _onlyPwScript = true; // no extension or proxy script: unsupported WebViews stay silent
  int? _proxyId;
  final Map<String, String> _parent = {}; // tab id -> tab it was opened from (this session)
  final ValueNotifier<ProxyGeo?> _geo = ValueNotifier<ProxyGeo?>(null);
  final ValueNotifier<bool> _geoBusy = ValueNotifier<bool>(false);
  List<String> _extScripts = const [];
  bool _adBlock = false;

  Future<void> _init() async {
    try {
      // Fail closed: if this profile's proxy cannot be applied, the profile does not open.
      await _proxy.applyFor(_p.id);
      ProxyService.owner = _p.id;
      _proxyId = (await _proxy.proxyFor(_p.id))?.id;
      _refreshGeo();
      _pwOn = (await widget.service.getSetting(_p.id, 'pw_enabled')) != '0';
      _extScripts = await _scriptsForProfile();
      _adBlock = await _ext.adBlockEnabledFor(_p.id);
      _engine = SearchEngines.byId(await widget.service.getSetting(_p.id, 'search_engine'));
      _tabs.desktopDefault = _p.desktopMode;
      await _tabs.load();
      final first = widget.initialUrl;
      if (first != null && first.isNotEmpty) {
        await _tabs.addTab(url: first, desktop: _p.desktopMode);
      }
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
    if (ProxyService.owner == _p.id) {
      ProxyService.owner = null;
      KMultiProfiles.clearProxy().then<void>((_) {}, onError: (Object e) {});
    }
    _tabs.removeListener(_onTabsChanged);
    _tabs.dispose();
    _focus.dispose();
    _url.dispose();
    _findFocus.dispose();
    _findText.dispose();
    _geo.dispose();
    _geoBusy.dispose();
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
    if (_finding && _tabs.activeId != _findTabId) {
      _ctl[_findTabId]?.clearFind();
      _finding = false;
      _findTabId = null;
    }
    setState(() {});
  }

  void _openFind() {
    final id = _tabs.activeId;
    if (id == null || _ctl[id] == null) {
      _toast('Open a page first');
      return;
    }
    _focus.unfocus();
    _findText.clear();
    setState(() {
      _finding = true;
      _findTabId = id;
    });
    _findFocus.requestFocus();
  }

  void _closeFind() {
    _ctl[_findTabId]?.clearFind();
    _findFocus.unfocus();
    setState(() {
      _finding = false;
      _findTabId = null;
    });
  }

  Widget _findBar(KWebViewController? c) {
    final f = c?.find.value ?? const KFindState();
    final hasText = _findText.text.isNotEmpty;
    final label = hasText ? '${f.active}/${f.total}' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _findText,
              focusNode: _findFocus,
              textInputAction: TextInputAction.search,
              onChanged: (v) => c?.findAll(v),
              onSubmitted: (_) {
                c?.findNext(true);
                _findFocus.requestFocus();
              },
              decoration: InputDecoration(
                hintText: 'Find in page',
                isDense: true,
                filled: true,
                fillColor: context.panel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    widthFactor: 1,
                    child: Text(label, style: TextStyle(fontSize: 12, color: context.muted)),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Previous match',
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: f.total > 0 ? () => c?.findNext(false) : null,
          ),
          IconButton(
            tooltip: 'Next match',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: f.total > 0 ? () => c?.findNext(true) : null,
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _closeFind,
          ),
        ],
      ),
    );
  }

  void _syncUrlText() {
    if (_focus.hasFocus) return;
    final t = _tabs.active;
    _url.text = (t == null || t.url == kHomeUrl) ? '' : t.url;
  }

  void _onFocus() {
    if (mounted) setState(() {});
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

  /// Extension scripts plus the WebRTC guard when this profile uses a proxy.
  Future<List<String>> _scriptsForProfile() async {
    final base = [...await _ext.scriptsFor(_p.id), ...await _proxy.guardScripts(_p.id)];
    _onlyPwScript = base.isEmpty;
    return [...base, if (_pwOn) passwordCaptureScript];
  }

  /// Destroys this browser's WebViews so the proxy can be changed for another profile.
  Future<void> _releaseWebViews() async {
    setState(() {
      _switching = true;
      _live.clear();
      _ctl.clear();
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  void _applyAdBlock(KWebViewController c) {
    c.setAdBlock(_adBlock).then<void>((_) {}, onError: (Object e) {});
  }

  void _applyExtensions(KWebViewController c) {
    c.setExtensions(_extScripts).then<void>((_) {}, onError: (Object e) {
      if (_onlyPwScript && e is PlatformException && e.code == 'unsupported') return;
      _toast('Extensions could not be applied: $e');
    });
  }

  /// Looks up where this profile exits to the internet (shown in the menu): through the
  /// proxy when the profile has one, otherwise the phone's own connection.
  Future<void> _refreshGeo({bool force = false}) async {
    final id = _proxyId;
    _geoBusy.value = true;
    try {
      final g = id == null
          ? await _proxy.directGeoFor(refresh: force)
          : await _proxy.geoFor(id, refresh: force);
      if (mounted && _proxyId == id) _geo.value = g;
    } catch (_) {
      if (mounted && _proxyId == id) _geo.value = null;
    } finally {
      if (mounted) _geoBusy.value = false;
    }
  }

  /// Quick disconnect from the menu: this profile's proxy becomes None.
  Future<void> _disconnectProxy() async {
    try {
      await KMultiProfiles.clearProxy(); // first: if this fails nothing has changed
      await _proxy.setProxyFor(_p.id, null);
    } catch (e) {
      _toast('Could not disconnect the proxy: $e');
      return;
    }
    await _syncAfterProxyChange();
    _toast('Proxy disconnected. This profile now uses your real IP address.');
  }

  Future<void> _onLoginSubmitted(String url, String user, String pass) async {
    if (!_pwOn || pass.isEmpty) return;
    try {
      final r = await _pw.check(url, user, pass);
      if (!mounted || r == PwCheck.invalid || r == PwCheck.same) return;
      final host = Uri.tryParse(url)?.host ?? '';
      final who = user.isEmpty ? host : '$user on $host';
      final changed = r == PwCheck.changed;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(changed ? 'Update saved password for $who?' : 'Save password for $who?'),
            duration: const Duration(seconds: 15),
            action: SnackBarAction(
              label: changed ? 'Update' : 'Save',
              onPressed: () async {
                try {
                  await _pw.store(url, user, pass);
                  _toast('Password saved');
                } catch (e) {
                  _toast('Could not save: $e');
                }
              },
            ),
          ),
        );
    } catch (_) {}
  }

  Future<void> _onLoginForm(KWebViewController c, String url) async {
    if (!_pwOn || c != _activeCtl) return;
    final origin = PasswordService.originOf(url);
    if (origin == null) return;
    try {
      final logins = await _pw.forOrigin(origin);
      if (!mounted || logins.isEmpty) return;
      final one = logins.length == 1;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(one
                ? 'Fill saved login${logins.first.username.isEmpty ? '' : ': ${logins.first.username}'}?'
                : 'Saved logins for ${logins.first.host}'),
            duration: const Duration(seconds: 12),
            action: SnackBarAction(
              label: one ? 'Fill' : 'Choose',
              onPressed: () => one ? _fillLogin(c, logins.first) : _chooseLogin(c, logins),
            ),
          ),
        );
    } catch (_) {}
  }

  Future<void> _fillLogin(KWebViewController c, SavedLogin l) async {
    try {
      final p = await _pw.reveal(l.id);
      await c.fillLogin(l.username, p);
    } catch (e) {
      _toast('Could not fill: $e');
    }
  }

  Future<void> _chooseLogin(KWebViewController c, List<SavedLogin> logins) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final l in logins)
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(l.username.isEmpty ? '(no username)' : l.username),
                subtitle: Text(l.host),
                onTap: () {
                  Navigator.pop(ctx);
                  _fillLogin(c, l);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPasswords() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PasswordsScreen(profile: _p, passwords: _pw, service: widget.service),
      ),
    );
    final on = (await widget.service.getSetting(_p.id, 'pw_enabled')) != '0';
    if (!mounted || on == _pwOn) return;
    _pwOn = on;
    _extScripts = await _scriptsForProfile();
    for (final c in _ctl.values) {
      _applyExtensions(c);
    }
    if (!_onStart) _activeCtl?.reload();
  }

  Future<void> _openRecentTabs() async {
    final rows = await _history.list(limit: 60);
    final seen = <String>{};
    final recent = <HistoryEntry>[];
    for (final h in rows) {
      if (seen.add(h.url)) recent.add(h);
      if (recent.length >= 10) break;
    }
    if (!mounted) return;
    await showRecentTabs(
      context,
      closed: _tabs.recentlyClosed.reversed.toList(),
      visited: recent,
      onOpenClosed: (t) => _tabs.reopenTab(t),
      onOpenUrl: (url) => _tabs.addTab(url: url, desktop: _p.desktopMode),
    );
  }

  Future<void> _deleteBrowsingData() async {
    final what = await showClearDataDialog(context, profileName: _p.displayName);
    if (what == null || what.isEmpty || !mounted) return;
    try {
      if (what.contains('history')) await _history.clear();
      if (what.contains('passwords')) await _pw.deleteAll();
      if (what.contains('cookies')) {
        await KMultiProfiles.clearSiteData(_p.engineProfileName, cookies: true, storage: true);
      }
      if (what.contains('cache')) {
        for (final c in _ctl.values) {
          await c.clearCache();
        }
      }
      _toast('Browsing data deleted');
      if (what.contains('cookies') && !_onStart) _activeCtl?.reload();
    } catch (e) {
      _toast('Could not delete: $e');
    }
  }

  Future<void> _openExtensions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileExtensionsScreen(profile: _p, extensions: _ext, proxy: _proxy),
      ),
    );
    try {
      await _proxy.applyFor(_p.id);
    } catch (e) {
      _toast('Proxy could not be applied: $e');
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await _syncAfterProxyChange();
  }

  /// Re-reads this profile's proxy, scripts and ad blocker and applies what changed to the
  /// open tabs (the page reloads when something changed).
  Future<void> _syncAfterProxyChange() async {
    final proxyId = (await _proxy.proxyFor(_p.id))?.id;
    final scripts = await _scriptsForProfile();
    final adBlock = await _ext.adBlockEnabledFor(_p.id);
    final proxyChanged = proxyId != _proxyId;
    if (!mounted || (!proxyChanged && listEquals(scripts, _extScripts) && adBlock == _adBlock)) return;
    _proxyId = proxyId;
    if (proxyChanged) {
      _geo.value = null;
      _refreshGeo();
    }
    _extScripts = scripts;
    _adBlock = adBlock;
    for (final c in _ctl.values) {
      _applyAdBlock(c);
      _applyExtensions(c);
    }
    if (!_onStart) _activeCtl?.reload();
  }

  void _attach(String tabId, KWebViewController c) {
    _ctl[tabId] = c;
    _applyAdBlock(c);
    if (_extScripts.isNotEmpty) _applyExtensions(c);
    c.onNewWindow = (u) {
      _tabs.addTab(url: u, desktop: _p.desktopMode).then((t) => _parent[t.id] = tabId);
    };
    c.onDownloadMessage = _toast;
    c.onLoginSubmitted = (url, user, pass) => _onLoginSubmitted(url, user, pass);
    c.onLoginForm = (url) => _onLoginForm(c, url);
    c.onDownloadStart = (info) => _downloads.started(_p.id, info);
    c.onDownloadProgress = (info) => _downloads.progress(_p.id, info);
    c.onDownloadFailed = (info) => _downloads.failed(info);
    c.onDownloadDone = (info) {
      _downloads.add(_p.id, info);
    };
    c.state.addListener(() {
      if (!mounted) return;
      final s = c.state.value;
      if (s.url == 'about:blank') {
        if (s.finished) _tabs.updatePage(tabId, kHomeUrl, '');
      } else if (s.url.isNotEmpty) {
        _tabs.updatePage(tabId, s.url, s.title);
      }
      if (s.finished && s.url.isNotEmpty && !s.url.startsWith(_testBase)) {
        _history.record(s.url, s.title);
      }
      setState(() {});
    });
    c.find.addListener(() {
      if (mounted && _finding && tabId == _findTabId) setState(() {});
    });
    c.progress.addListener(() {
      if (mounted && tabId == _tabs.activeId) setState(() {});
    });
    for (final t in _tabs.tabs) {
      if (t.id != tabId) continue;
      if (t.desktopMode) c.setDesktopMode(true, reload: false);
      if (t.url.startsWith(_testBase)) {
        c.loadTestPage();
      } else if (t.url.isNotEmpty && t.url != kHomeUrl) {
        c.loadUrl(t.url);
      }
      break;
    }
    if (mounted) setState(() {});
  }

  void _go() {
    _focus.unfocus();
    if (_url.text.trim().isEmpty) {
      _goHome();
      return;
    }
    _open(resolveInput(_url.text, _engine));
  }

  /// Loads [u] in the active tab.
  void _open(String u) {
    final id = _tabs.activeId;
    if (id == null) return;
    final c = _ctl[id];
    if (c != null) {
      c.loadUrl(u);
    } else {
      _tabs.updatePage(id, u, '');
    }
  }

  /// Shows the start page in the active tab (the WebView is blanked).
  void _goHome({int tab = 0}) {
    final id = _tabs.activeId;
    if (id == null) return;
    _startTab = tab;
    _ctl[id]?.loadUrl('about:blank');
    _tabs.updatePage(id, kHomeUrl, '');
  }

  bool get _onStart {
    final u = _tabs.active?.url ?? '';
    return u.isEmpty || u == kHomeUrl;
  }

  /// Takes a small picture of the active page for the tab switcher.
  Future<void> _captureThumb() async {
    final id = _tabs.activeId;
    if (id == null || _onStart) return;
    try {
      final bytes = await _ctl[id]?.captureThumbnail();
      if (bytes != null && bytes.isNotEmpty) ThumbnailCache.put(id, bytes);
    } catch (_) {}
  }

  Future<void> _newTab() async {
    await _captureThumb();
    _startTab = 0;
    final from = _tabs.activeId;
    final t = await _tabs.addTab(url: kHomeUrl, desktop: _p.desktopMode);
    if (from != null) _parent[t.id] = from;
  }

  /// Back button: page history first; then the tab this one was opened from (this tab
  /// closes); then the profile's start page; only from the start page does it leave the profile.
  Future<void> _handleBack() async {
    final id = _tabs.activeId;
    final c = _activeCtl;
    if (!_onStart && (c?.state.value.canGoBack ?? false)) {
      c?.goBack();
      return;
    }
    final parent = id == null ? null : _parent[id];
    if (id != null && parent != null && _tabs.tabs.any((t) => t.id == parent)) {
      _parent.remove(id);
      await _tabs.select(parent);
      await _tabs.close(id);
      return;
    }
    if (!_onStart) {
      _goHome();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _openSettings() {
    _focus.unfocus();
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  void _openPrivate() {
    _focus.unfocus();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => PrivateBrowserScreen(engine: _engine)),
    );
  }

  Future<void> _toggleBookmark(String url, String title, bool marked) async {
    if (marked) {
      await _bookmarks.removeUrl(url);
      _toast('Bookmark removed');
      return;
    }
    final r = await showBookmarkDialog(context, url: url, title: title, editableUrl: false);
    if (r == null) return;
    await _addBookmark(r.url, r.title, r.addToHome);
  }

  Future<void> _addBookmark(String url, String title, bool addToHome) async {
    await _bookmarks.add(url, title);
    if (!addToHome) {
      _toast('Bookmark added');
      return;
    }
    final added = await HomeService(widget.service.db).add(url: url, title: title);
    _toast(added ? 'Bookmark added, and shown on Home' : 'Bookmark added (already on Home)');
  }

  Future<void> _toggleDesktop() async {
    final t = _tabs.active;
    if (t == null) return;
    final next = !t.desktopMode;
    await _tabs.setDesktop(t.id, next);
    _ctl[t.id]?.setDesktopMode(next);
  }

  /// Opens this profile's Downloads list (also used by the button in the address bar).
  void _openDownloads() {
    _focus.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DownloadsScreen(profile: _p, downloads: _downloads),
      ),
    );
  }

  Future<void> _openSwitcher() async {
    _focus.unfocus();
    await _captureThumb();
    if (!mounted) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => TabSwitcherScreen(tabs: _tabs, profile: _p)),
    );
    if (result == TabSwitcherScreen.switchProfile && mounted) _showProfileSwitcher();
  }

  Future<void> _openHistory() async {
    _focus.unfocus();
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => HistoryScreen(history: _history, profileName: _p.displayName),
      ),
    );
    if (url != null && mounted) _activeCtl?.loadUrl(url);
  }

  /// Switch to another profile (its own browser, tabs and sessions) or go back
  /// to the dashboard. This browser is closed first, so its WebViews are destroyed.
  void _showProfileSwitcher() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final list = [...widget.service.profiles]..sort((a, b) => a.number.compareTo(b.number));
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.grid_view),
                  title: const Text('All profiles'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).pop();
                  },
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in list)
                        ListTile(
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: ProfileStyle.colorFor(p.color),
                            child: Icon(ProfileStyle.iconFor(p.icon), size: 16, color: Colors.white),
                          ),
                          title: Text(p.displayName),
                          trailing: p.id == _p.id ? const Icon(Icons.check) : null,
                          onTap: () async {
                            Navigator.pop(ctx);
                            if (p.id == _p.id) return;
                            await _releaseWebViews();
                            if (!mounted) return;
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) => BrowserScreen(profile: p, service: widget.service),
                              ),
                            );
                          },
                        ),
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
    });
  }

  Future<void> _openMenu() async {
    _focus.unfocus();
    final t = _tabs.active;
    final url = t?.url ?? '';
    final marked = url.startsWith('http') && await _bookmarks.contains(url);
    if (!mounted) return;
    final c = _activeCtl;
    final canBack = c?.state.value.canGoBack ?? false;
    final canForward = c?.state.value.canGoForward ?? false;
    final loading = (c?.progress.value ?? 1.0) < 1.0;
    final onStart = _onStart;
    showTopMenu(
      context,
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
                ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: ProfileStyle.colorFor(_p.color),
                    child: Icon(ProfileStyle.iconFor(_p.icon), size: 16, color: Colors.white),
                  ),
                  title: Text(_p.displayName),
                  subtitle: const Text('Switch profile'),
                  trailing: const Icon(Icons.swap_horiz),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showProfileSwitcher();
                  },
                ),
                const Divider(height: 1),
                AnimatedBuilder(
                  animation: Listenable.merge([_geo, _geoBusy]),
                  builder: (_, __) {
                    final g = _geo.value;
                    final on = _proxyId != null;
                    final busy = _geoBusy.value;
                    return ListTile(
                      leading: g != null && g.flag.isNotEmpty
                          ? Text(g.flag, style: const TextStyle(fontSize: 22))
                          : Icon(on ? Icons.vpn_lock_outlined : Icons.public),
                      title: Text(g != null ? g.country : (busy ? 'Checking location...' : 'Location unknown')),
                      subtitle: Text(g != null
                          ? '${on ? 'Proxy' : 'No proxy'}  |  ${g.code.toUpperCase()}  ${g.ip}'
                          : (busy
                              ? (on ? 'Proxy is on' : 'No proxy')
                              : (on ? 'Proxy is on. Tap to retry' : 'No proxy. Tap to retry'))),
                      onTap: busy ? null : () => _refreshGeo(force: true),
                    );
                  },
                ),
                if (_proxyId != null)
                  item(Icons.link_off, 'Disconnect proxy', _disconnectProxy),
                const Divider(height: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: canBack
                          ? () {
                              Navigator.pop(ctx);
                              c?.goBack();
                            }
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Forward',
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: canForward
                          ? () {
                              Navigator.pop(ctx);
                              c?.goForward();
                            }
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Downloads',
                      icon: const Icon(Icons.download_outlined),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openDownloads();
                      },
                    ),
                    IconButton(
                      tooltip: marked ? 'Remove bookmark' : 'Add bookmark',
                      icon: Icon(marked ? Icons.star : Icons.star_border),
                      onPressed: url.startsWith('http')
                          ? () {
                              Navigator.pop(ctx);
                              _toggleBookmark(url, t?.title ?? '', marked);
                            }
                          : null,
                    ),
                  ],
                ),
                const Divider(height: 1),
                item(Icons.add, 'New Tab', _newTab),
                item(Icons.visibility_off_outlined, 'New private tab', _openPrivate),
                if (_tabs.recentlyClosed.isNotEmpty)
                  item(Icons.undo, 'Reopen closed tab', () => _tabs.reopenClosed()),
                item(Icons.restore, 'Recent tabs', _openRecentTabs),
                if (t != null) item(Icons.copy_all_outlined, 'Duplicate tab', () => _tabs.duplicate(t.id)),
                item(
                  Icons.desktop_windows_outlined,
                  'Desktop site',
                  _toggleDesktop,
                  trailing: IgnorePointer(
                    child: Switch(value: t?.desktopMode ?? false, onChanged: (_) {}),
                  ),
                ),
                if (url.startsWith('http'))
                  item(
                    marked ? Icons.bookmark : Icons.bookmark_add_outlined,
                    marked ? 'Remove bookmark' : 'Add to bookmarks',
                    () => _toggleBookmark(url, t?.title ?? '', marked),
                  ),
                item(Icons.bookmarks_outlined, 'Bookmarks', () => _goHome(tab: 1)),
                if (!_onStart) item(Icons.find_in_page_outlined, 'Find in page', _openFind),
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
                item(Icons.history, 'History', _openHistory),
                item(Icons.cleaning_services_outlined, 'Delete browsing data', _deleteBrowsingData),
                item(
                  Icons.download_outlined,
                  'Downloads',
                  _openDownloads,
                ),
                item(Icons.key_outlined, 'Passwords', _openPasswords),
                item(Icons.search, 'Search engine: ${_engine.name}', _pickEngine),
                item(
                  Icons.extension_outlined,
                  _adBlock && (c?.state.value.blocked ?? 0) > 0
                      ? 'Extensions (${c?.state.value.blocked} blocked)'
                      : 'Extensions',
                  _openExtensions,
                ),
                item(Icons.public, 'Check my IP', () => _tabs.addTab(url: 'https://api.ipify.org', desktop: false)),
                item(Icons.settings_outlined, 'Settings', _openSettings),
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
      child: (!_switching && _live.contains(id))
          ? KProfileWebView(
              key: ValueKey('wv_$id'),
              profile: _p.engineProfileName,
              onCreated: (c) => _attach(id, c),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _tabCountButton() {
    return InkResponse(
      onTap: _openSwitcher,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 1.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${_tabs.tabs.length}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
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

    final active = _tabs.active;
    final activeIndex = _tabs.tabs.indexWhere((t) => t.id == _tabs.activeId);
    final c = _activeCtl;
    final progress = c?.progress.value ?? 1.0;
    final loading = progress < 1.0;
    final secure = (active?.url ?? '').startsWith('https://');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_finding) {
          _closeFind();
        } else if (_focus.hasFocus) {
          _focus.unfocus();
        } else {
          _handleBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
          children: [
            if (_finding) _findBar(c) else Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
              child: Row(children: [
              IconButton(
                tooltip: 'Home',
                icon: const Icon(Icons.home_outlined),
                onPressed: _goHome,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 38, height: 40),
              ),
              Expanded(child: TextField(
                controller: _url,
                focusNode: _focus,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _go(),
                decoration: InputDecoration(
                  hintText: 'Search or enter address',
                  isDense: true,
                  filled: true,
                  fillColor: context.panel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(secure ? Icons.lock_outline : Icons.public, size: 18),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  suffixIcon: _focus.hasFocus
                      ? IconButton(
                          tooltip: 'Clear',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _url.clear();
                            _focus.requestFocus();
                          },
                        )
                      : IconButton(
                          tooltip: loading ? 'Stop' : 'Reload',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                          icon: Icon(loading ? Icons.close : Icons.refresh, size: 20),
                          onPressed: () => loading ? c?.stop() : c?.reload(),
                        ),
                ),
              )),
              IconButton(
                tooltip: 'New tab',
                icon: const Icon(Icons.add),
                onPressed: _newTab,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 38, height: 40),
              ),
              _tabCountButton(),
              IconButton(
                tooltip: 'Menu',
                icon: const Icon(Icons.more_vert),
                onPressed: _openMenu,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 36, height: 40),
              ),
              ]),
            ),
            SizedBox(
              height: 2,
              child: loading ? LinearProgressIndicator(value: progress, minHeight: 2) : null,
            ),
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: activeIndex < 0 ? 0 : activeIndex,
                    children: [for (final t in _tabs.tabs) _tabView(t.id)],
                  ),
                  if (_onStart)
                    Positioned.fill(
                      child: StartPage(
                        key: ValueKey('start_${_tabs.activeId}_$_startTab'),
                        profileName: _p.displayName,
                        engine: _engine,
                        history: _history,
                        bookmarks: _bookmarks,
                        initialTab: _startTab,
                        onOpen: _open,
                        onOpenHistory: _openHistory,
                        onAddBookmark: _addBookmark,
                        home: _home,
                        profileId: _p.id,
                      ),
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
}
