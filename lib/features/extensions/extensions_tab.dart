import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/user_extension.dart';
import '../../services/extension_service.dart';
import '../../services/proxy_service.dart';
import '../proxy/proxies_screen.dart';
import 'userscript.dart';

Future<String> _fetch(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw const ExtensionError('Enter a full link that starts with https://');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw ExtensionError('The server answered ${res.statusCode}.');
    final bytes = <int>[];
    await for (final chunk in res) {
      bytes.addAll(chunk);
      if (bytes.length > maxScriptBytes) throw const ExtensionError('The file is too large (limit 300 KB).');
    }
    return utf8.decode(bytes, allowMalformed: true);
  } on ExtensionError {
    rethrow;
  } catch (e) {
    throw ExtensionError('Could not download: $e');
  } finally {
    client.close();
  }
}

String _fallbackName(String url) {
  final seg = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
  if (seg.isEmpty) return '';
  return seg.last.replaceAll(RegExp(r'\.user\.js$|\.js$'), '');
}

Future<bool> _confirmInstall(BuildContext context, ParsedUserscript p, {bool update = false}) async {
  final sites = p.runsEverywhere ? 'All websites' : p.matches.take(5).join('\n');
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(update ? 'Update "${p.name}"?' : 'Add "${p.name}"?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.version.isNotEmpty) Text('Version ${p.version}'),
            if (p.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.description)),
            const SizedBox(height: 10),
            const Text('Runs on', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(sites),
            const SizedBox(height: 10),
            const Text(
              'An extension can read and change the pages it runs on. It is added to the library only; '
              'you choose later which profiles turn it on.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(update ? 'Update' : 'Add')),
      ],
    ),
  );
  return r == true;
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// "Add extension": paste code or download from a link.
Future<void> showAddExtensionFlow(BuildContext context, ExtensionService service) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('From a link'),
            subtitle: const Text('Download a .user.js script once'),
            onTap: () => Navigator.pop(ctx, 'link'),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('Paste code'),
            subtitle: const Text('Paste the whole script'),
            onTap: () => Navigator.pop(ctx, 'paste'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final text = await showDialog<String>(
    context: context,
    builder: (_) => _InputDialog(link: choice == 'link'),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  try {
    String? source;
    var code = text;
    if (choice == 'link') {
      source = text.trim();
      code = await _fetch(source);
    }
    final parsed = parseUserscript(code, fallbackName: source == null ? null : _fallbackName(source));
    if (!context.mounted) return;
    if (!await _confirmInstall(context, parsed)) return;
    await service.add(parsed, sourceUrl: source);
    if (context.mounted) _toast(context, '"${parsed.name}" added to the library');
  } catch (e) {
    if (context.mounted) _toast(context, e.toString());
  }
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.link});
  final bool link;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.link ? 'Extension link' : 'Paste extension code'),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        keyboardType: widget.link ? TextInputType.url : TextInputType.multiline,
        minLines: widget.link ? 1 : 8,
        maxLines: widget.link ? 1 : 12,
        decoration: InputDecoration(
          hintText: widget.link ? 'https://.../script.user.js' : '// ==UserScript==\n// @name ...',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctl.text), child: const Text('Next')),
      ],
    );
  }
}

/// The Extensions tab of the main Home: the only place extensions are added.
class ExtensionsTab extends StatelessWidget {
  const ExtensionsTab({super.key, required this.service, required this.proxy});
  final ExtensionService service;
  final ProxyService proxy;

  Future<void> _update(BuildContext context, UserExtension e) async {
    try {
      final code = await _fetch(e.sourceUrl!);
      final parsed = parseUserscript(code, fallbackName: e.name);
      if (!context.mounted) return;
      if (!await _confirmInstall(context, parsed, update: true)) return;
      await service.replace(e.id, parsed, sourceUrl: e.sourceUrl);
      if (context.mounted) _toast(context, 'Updated');
    } catch (err) {
      if (context.mounted) _toast(context, err.toString());
    }
  }

  Future<void> _remove(BuildContext context, UserExtension e) async {
    final n = service.usage[e.id] ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${e.name}"?'),
        content: Text(n == 0
            ? 'It is removed from the library.'
            : 'It is removed from the library and turned off in $n ${n == 1 ? 'profile' : 'profiles'}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await service.delete(e.id);
  }

  Widget _proxyCard(BuildContext context) {
    return ListenableBuilder(
      listenable: proxy,
      builder: (context, _) {
        final n = proxy.proxies.length;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Material(
            color: context.panel,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => ProxiesScreen(proxy: proxy)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.purple,
                      child: Icon(Icons.vpn_key_outlined, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Proxy  (changes the IP address)',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          const Text(
                            'Add proxy servers once here. Each profile picks one.',
                            style: TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            n == 0 ? 'No proxies yet. Tap to add.' : '$n ${n == 1 ? 'proxy' : 'proxies'}  |  tap to manage',
                            style: TextStyle(fontSize: 11, color: context.muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _builtIn(BuildContext context) {
    final n = service.adBlockUsage;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: context.panel,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.gold,
                child: Icon(Icons.shield_outlined, color: AppColors.darkBase),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ad and tracker blocker  (built-in)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const Text(
                      'Blocks ad and tracker requests and hides empty ad boxes.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      service.adBlockAvailable
                          ? 'Available to profiles  |  on in $n ${n == 1 ? 'profile' : 'profiles'}'
                          : 'Hidden from profiles',
                      style: TextStyle(fontSize: 11, color: context.muted),
                    ),
                  ],
                ),
              ),
              Switch(value: service.adBlockAvailable, onChanged: service.setAdBlockAvailable),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final list = service.extensions;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          itemCount: list.isEmpty ? 3 : list.length + 2,
          itemBuilder: (_, i) {
            if (i == 0) return _builtIn(context);
            if (i == 1) return _proxyCard(context);
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No other extensions yet. Tap Add extension to add one from a link or by pasting code. '
                  'Each profile can then switch it on from its own menu.',
                  textAlign: TextAlign.center,
                ),
              );
            }
            final e = list[i - 2];
            final n = service.usage[e.id] ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Material(
                color: context.panel,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(
                    children: [
                      const CircleAvatar(backgroundColor: AppColors.purple, child: Icon(Icons.extension, color: Colors.white)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.version.isEmpty ? e.name : '${e.name}  ${e.version}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (e.description.isNotEmpty)
                              Text(e.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(
                              '${e.matches.isEmpty ? 'All sites' : e.matches.take(2).join(', ')}'
                              '  |  on in $n ${n == 1 ? 'profile' : 'profiles'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: context.muted),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'update') _update(context, e);
                          if (v == 'remove') _remove(context, e);
                        },
                        itemBuilder: (_) => [
                          if (e.sourceUrl != null) const PopupMenuItem(value: 'update', child: Text('Update from link')),
                          const PopupMenuItem(value: 'remove', child: Text('Remove')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
