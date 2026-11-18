import 'top_menu.dart';
import 'package:flutter/material.dart';
import 'package:kmulti_profiles/kmulti_profiles.dart';

import '../../core/theme/app_theme.dart';
import 'private_session.dart';
import 'url_utils.dart';

class _PTab {
  _PTab(this.id, this.url);
  final String id;
  String url;
  String title = '';
}

/// Private browser: tabs live in memory only (never in SQLite), no history, no
/// bookmarks, and the temporary engine profile is deleted when this closes.
class PrivateBrowserScreen extends StatefulWidget {
  const PrivateBrowserScreen({super.key, required this.engine});
  final SearchEngine engine;

  @override
  State<PrivateBrowserScreen> createState() => _PrivateBrowserScreenState();
}

class _PrivateBrowserScreenState extends State<PrivateBrowserScreen> {
  String? _profile;
  String? _error;
  final List<_PTab> _tabs = [];
  String? _activeId;
  final Map<String, KWebViewController> _ctl = {};
  final Set<String> _live = {};
  final TextEditingController _url = TextEditingController();
  final FocusNode _focus = FocusNode();
  int _seq = 0;

  _PTab? get _active {
    for (final t in _tabs) {
      if (t.id == _activeId) return t;
    }
    return null;
  }

  KWebViewController? get _activeCtl => _activeId == null ? null : _ctl[_activeId];

  bool get _onHome => (_active?.url ?? '').isEmpty;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (!_focus.hasFocus) _syncUrl();
    });
    _init();
  }

  Future<void> _init() async {
    try {
      final name = await PrivateSession.start();
      if (!mounted) {
        PrivateSession.destroy(name);
        return;
      }
      _profile = name;
      _addTab('');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    final name = _profile;
    _focus.dispose();
    _url.dispose();
    if (name != null) PrivateSession.destroy(name);
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _syncUrl() {
    if (_focus.hasFocus) return;
    _url.text = _active?.url ?? '';
  }

  void _addTab(String url) {
    final t = _PTab('p${_seq++}', url);
    setState(() {
      _tabs.add(t);
      _activeId = t.id;
      _live.add(t.id);
    });
    _syncUrl();
  }

  void _select(String id) {
    setState(() {
      _activeId = id;
      _live.add(id);
    });
    _syncUrl();
  }

  void _closeTab(String id) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    if (_tabs.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _tabs.removeAt(i);
      _ctl.remove(id);
      _live.remove(id);
      if (_activeId == id) {
        final next = _tabs[i.clamp(0, _tabs.length - 1)];
        _activeId = next.id;
        _live.add(next.id);
      }
    });
    _syncUrl();
  }

  void _attach(String tabId, KWebViewController c) {
    _ctl[tabId] = c;
    c.onNewWindow = (u) => _addTab(u);
    c.onDownloadMessage = _toast;
    c.state.addListener(() {
      if (!mounted) return;
      final s = c.state.value;
      for (final t in _tabs) {
        if (t.id != tabId) continue;
        if (s.url == 'about:blank') {
          if (s.finished) {
            t.url = '';
            t.title = '';
          }
        } else if (s.url.isNotEmpty) {
          t.url = s.url;
          t.title = s.title;
        }
        break;
      }
      _syncUrl();
      setState(() {});
    });
    c.progress.addListener(() {
      if (mounted && tabId == _activeId) setState(() {});
    });
    for (final t in _tabs) {
      if (t.id == tabId && t.url.isNotEmpty) c.loadUrl(t.url);
    }
    if (mounted) setState(() {});
  }

  void _open(String u) {
    _focus.unfocus();
    final t = _active;
    if (t == null) return;
    final c = _ctl[t.id];
    if (c != null) {
      c.loadUrl(u);
    } else {
      setState(() => t.url = u);
    }
  }

  void _go() {
    if (_url.text.trim().isEmpty) {
      _goHome();
      return;
    }
    _open(resolveInput(_url.text, widget.engine));
  }

  void _goHome() {
    final t = _active;
    if (t == null) return;
    _focus.unfocus();
    _ctl[t.id]?.loadUrl('about:blank');
    setState(() {
      t.url = '';
      t.title = '';
    });
    _syncUrl();
  }

  String _tabTitle(_PTab t) {
    if (t.url.isEmpty) return 'New private tab';
    if (t.title.isNotEmpty) return t.title;
    final host = Uri.tryParse(t.url)?.host ?? '';
    return host.isNotEmpty ? host : t.url;
  }

  void _showTabs() {
    _focus.unfocus();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('New private tab'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addTab('');
                  },
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final t in List<_PTab>.of(_tabs))
                        ListTile(
                          selected: t.id == _activeId,
                          leading: const Icon(Icons.visibility_off_outlined),
                          title: Text(_tabTitle(t), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            t.url.isEmpty ? 'Start page' : t.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Close tab',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              final last = _tabs.length == 1;
                              _closeTab(t.id);
                              if (last) {
                                Navigator.pop(ctx);
                              } else {
                                setSheet(() {});
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _select(t.id);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabCountButton() {
    return InkResponse(
      onTap: _showTabs,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.gold, width: 1.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${_tabs.length}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  void _openMenu() {
    _focus.unfocus();
    final c = _activeCtl;
    final canBack = c?.state.value.canGoBack ?? false;
    final canForward = c?.state.value.canGoForward ?? false;
    final loading = (c?.progress.value ?? 1.0) < 1.0 && !_onHome;
    final onHome = _onHome;
    showTopMenu(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: canBack && !onHome
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
                  tooltip: loading ? 'Stop' : 'Reload',
                  icon: Icon(loading ? Icons.close : Icons.refresh),
                  onPressed: onHome
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          if (loading) {
                            c?.stop();
                          } else {
                            c?.reload();
                          }
                        },
                ),
              ],
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New private tab'),
              onTap: () {
                Navigator.pop(ctx);
                _addTab('');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Exit private browsing'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabView(_PTab t) {
    return KeyedSubtree(
      key: ValueKey(t.id),
      child: _live.contains(t.id) && _profile != null
          ? KProfileWebView(
              key: ValueKey('pwv_${t.id}'),
              profile: _profile!,
              onCreated: (c) => _attach(t.id, c),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _home() {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
        children: [
          const Icon(Icons.visibility_off_outlined, size: 48, color: AppColors.gold),
          const SizedBox(height: 12),
          const Text(
            'Private browsing',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'No history, bookmarks or tabs are saved. Cookies and site data are deleted when you close this window. '
            'Files you download stay in your Downloads folder.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.muted),
          ),
          const SizedBox(height: 24),
          TextField(
            textInputAction: TextInputAction.go,
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) _open(resolveInput(v, widget.engine));
            },
            decoration: InputDecoration(
              hintText: 'Search ${widget.engine.name} or type an address',
              isDense: true,
              filled: true,
              fillColor: context.panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.search, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Private browsing')),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not open: $_error'))),
      );
    }
    if (_profile == null || _active == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Private browsing')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final c = _activeCtl;
    final progress = c?.progress.value ?? 1.0;
    final loading = progress < 1.0 && !_onHome;
    final canBack = c?.state.value.canGoBack ?? false;
    final secure = (_active?.url ?? '').startsWith('https://');
    final index = _tabs.indexWhere((t) => t.id == _activeId);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_focus.hasFocus) {
          _focus.unfocus();
        } else if (canBack && !_onHome) {
          c?.goBack();
        } else {
          _closeTab(_activeId!);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                color: context.panel,
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_off_outlined, size: 16, color: AppColors.gold),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Private - nothing is saved', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Exit'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
                child: Row(children: [
                IconButton(
                  tooltip: 'Start page',
                  icon: const Icon(Icons.home_outlined),
                  onPressed: _goHome,
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
                    prefixIcon: Icon(secure ? Icons.lock_outline : Icons.visibility_off_outlined, size: 18),
                    suffixIcon: _focus.hasFocus
                        ? IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _url.clear();
                              _focus.requestFocus();
                            },
                          )
                        : IconButton(
                            tooltip: loading ? 'Stop' : 'Reload',
                            icon: Icon(loading ? Icons.close : Icons.refresh, size: 20),
                            onPressed: () => loading ? c?.stop() : c?.reload(),
                          ),
                  ),
                )),
                _tabCountButton(),
                IconButton(
                  tooltip: 'Menu',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _openMenu(),
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
                      index: index < 0 ? 0 : index,
                      children: [for (final t in _tabs) _tabView(t)],
                    ),
                    if (_onHome) Positioned.fill(child: _home()),
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
