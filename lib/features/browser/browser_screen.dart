import 'package:flutter/material.dart';
import 'package:kmulti_profiles/kmulti_profiles.dart';

import '../../models/app_profile.dart';
import '../../services/profile_service.dart';
import '../profiles/profile_style.dart';

/// Opens exactly one profile. The WebView is created for this profile only and
/// destroyed when the screen closes (so the profile can be deleted afterwards).
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.profile, required this.service});
  final AppProfile profile;
  final ProfileService service;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  KWebViewController? _c;
  final TextEditingController _url = TextEditingController();

  AppProfile get _p => widget.profile;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _go() {
    final c = _c;
    var t = _url.text.trim();
    if (c == null || t.isEmpty) return;
    if (!t.contains('://')) t = 'https://$t';
    c.loadUrl(t);
  }

  Future<void> _cookies() async {
    final url = _c?.state.value.url ?? '';
    String text = '(no web page loaded yet)';
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

  @override
  Widget build(BuildContext context) {
    final color = ProfileStyle.colorFor(_p.color);
    final canBack = _c?.state.value.canGoBack ?? false;
    final canForward = _c?.state.value.canGoForward ?? false;
    return PopScope(
      canPop: !canBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _c?.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color,
                child: Icon(ProfileStyle.iconFor(_p.icon), size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(_p.displayName, overflow: TextOverflow.ellipsis)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Isolation test page',
              icon: const Icon(Icons.science_outlined),
              onPressed: () => _c?.loadTestPage(),
            ),
            IconButton(
              tooltip: 'Show cookies',
              icon: const Icon(Icons.cookie_outlined),
              onPressed: _cookies,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
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
            Expanded(
              child: KProfileWebView(
                key: ValueKey(_p.engineProfileName),
                profile: _p.engineProfileName,
                onCreated: (c) {
                  c.state.addListener(() {
                    if (!mounted) return;
                    final u = c.state.value.url;
                    if (u.isNotEmpty) _url.text = u;
                    setState(() {});
                  });
                  setState(() => _c = c);
                  c.loadTestPage();
                  widget.service.touchActive(_p.id);
                },
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
                    onPressed: canBack ? () => _c?.goBack() : null,
                  ),
                  IconButton(
                    tooltip: 'Forward',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: canForward ? () => _c?.goForward() : null,
                  ),
                  IconButton(
                    tooltip: 'Reload',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _c?.reload(),
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
