import 'package:flutter/material.dart';
import 'package:kmulti_profiles/kmulti_profiles.dart';

import '../../core/theme/app_theme.dart';

class _PocProfile {
  const _PocProfile(this.id, this.name);
  final String id; // permanent engine profile name
  final String name; // display name
}

const _profiles = <_PocProfile>[
  _PocProfile('km_001', 'Profile 1'),
  _PocProfile('km_002', 'Profile 2'),
];

class PocScreen extends StatefulWidget {
  const PocScreen({super.key});

  @override
  State<PocScreen> createState() => _PocScreenState();
}

class _PocScreenState extends State<PocScreen> {
  bool _loading = true;
  bool _supported = false;
  String _status = 'Checking multi-profile support...';
  List<String> _existing = const [];
  int _active = 0;
  final Map<String, KWebViewController> _controllers = {};
  final TextEditingController _url = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final info = await KMultiProfiles.info();
      final supported = info['supported'] == true;
      final version = info['webViewVersion'] ?? 'unknown';
      if (!supported) {
        setState(() {
          _loading = false;
          _supported = false;
          _status =
              'Multi-Profile API NOT supported by this WebView ($version). Profiles are disabled; no shared-storage fallback is used.';
        });
        return;
      }
      for (final p in _profiles) {
        await KMultiProfiles.ensureProfile(p.id);
      }
      final names = await KMultiProfiles.listProfiles();
      setState(() {
        _loading = false;
        _supported = true;
        _existing = names;
        _status = 'Multi-Profile API supported. WebView $version.';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _supported = false;
        _status = 'Initialisation failed: $e';
      });
    }
  }

  KWebViewController? get _activeController =>
      _controllers[_profiles[_active].id];

  void _go() {
    final c = _activeController;
    if (c == null) return;
    var text = _url.text.trim();
    if (text.isEmpty) return;
    if (!text.contains('://')) text = 'https://$text';
    c.loadUrl(text);
  }

  Future<void> _showCookies() async {
    final lines = <String>[];
    for (final p in _profiles) {
      final url = _controllers[p.id]?.state.value.url ?? '';
      String cookies = '(no page yet)';
      if (url.startsWith('http')) {
        try {
          cookies = await KMultiProfiles.cookies(p.id, url) ?? '(none)';
        } catch (e) {
          cookies = 'error: $e';
        }
      }
      lines.add('${p.name} [${p.id}]\n$url\n$cookies');
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Native cookies per profile'),
        content: SingleChildScrollView(child: SelectableText(lines.join('\n\n'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('K-Multi Browser'),
        actions: [
          if (_supported) ...[
            IconButton(
              tooltip: 'Open isolation test page',
              icon: const Icon(Icons.science_outlined),
              onPressed: () => _activeController?.loadTestPage(),
            ),
            IconButton(
              tooltip: 'Show cookies',
              icon: const Icon(Icons.cookie_outlined),
              onPressed: _showCookies,
            ),
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () => _activeController?.reload(),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: _supported
                      ? AppColors.purple.withOpacity(0.18)
                      : Colors.red.withOpacity(0.25),
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    '$_status\nProfiles in engine: ${_existing.join(", ")}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (_supported) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: SegmentedButton<int>(
                      segments: [
                        for (var i = 0; i < _profiles.length; i++)
                          ButtonSegment<int>(
                            value: i,
                            label: Text(_profiles[i].name),
                            icon: const Icon(Icons.person_outline),
                          ),
                      ],
                      selected: {_active},
                      onSelectionChanged: (s) {
                        setState(() => _active = s.first);
                        final st = _activeController?.state.value;
                        _url.text = st?.url ?? '';
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _url,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.go,
                            onSubmitted: (_) => _go(),
                            decoration: const InputDecoration(
                              hintText: 'Enter a website address',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(onPressed: _go, child: const Text('Go')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: IndexedStack(
                      index: _active,
                      children: [
                        for (final p in _profiles)
                          KProfileWebView(
                            key: ValueKey(p.id),
                            profile: p.id,
                            onCreated: (c) {
                              _controllers[p.id] = c;
                              c.state.addListener(() {
                                if (_profiles[_active].id == p.id &&
                                    c.state.value.url.isNotEmpty) {
                                  _url.text = c.state.value.url;
                                }
                              });
                              c.loadTestPage();
                            },
                          ),
                      ],
                    ),
                  ),
                ] else
                  const Expanded(child: SizedBox()),
              ],
            ),
    );
  }
}
