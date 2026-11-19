import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/proxy_entry.dart';
import '../../services/proxy_service.dart';

/// Add, edit and delete proxies. Opened from the Proxy card on the main Home.
class ProxiesScreen extends StatelessWidget {
  const ProxiesScreen({super.key, required this.proxy});
  final ProxyService proxy;

  Future<void> _edit(BuildContext context, [ProxyEntry? existing]) async {
    final r = await showDialog<_ProxyInput>(
      context: context,
      builder: (_) => _ProxyDialog(existing: existing),
    );
    if (r == null) return;
    if (existing == null) {
      await proxy.add(
        name: r.name,
        scheme: r.scheme,
        host: r.host,
        port: r.port,
        username: r.username,
        password: r.password,
      );
    } else {
      await proxy.update(
        existing.id,
        name: r.name,
        scheme: r.scheme,
        host: r.host,
        port: r.port,
        username: r.username,
        password: r.password,
      );
    }
  }

  /// Adds many proxies at once from pasted text (one proxy per line).
  Future<void> _import(BuildContext context) async {
    final r = await showDialog<_ImportInput>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (r == null) return;
    final bad = <String>[];
    final items = parseProxyList(r.text, bad);
    var added = 0;
    var skipped = 0;
    for (var i = 0; i < items.length; i++) {
      final p = items[i];
      final scheme = p.scheme ?? r.scheme;
      final exists = proxy.proxies.any((e) => e.host == p.host && e.port == p.port && e.scheme == scheme);
      if (exists) {
        skipped++;
        continue;
      }
      final name = r.prefix.isEmpty ? p.host : '${r.prefix} ${added + 1}';
      await proxy.add(
        name: name,
        scheme: scheme,
        host: p.host,
        port: p.port,
        username: p.user,
        password: p.pass,
      );
      added++;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          'Added $added'
          '${skipped > 0 ? ', $skipped already existed' : ''}'
          '${bad.isNotEmpty ? ', ${bad.length} lines not understood' : ''}',
        ),
      ));
  }

  Future<void> _delete(BuildContext context, ProxyEntry e) async {
    final n = proxy.usage[e.id] ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${e.name}"?'),
        content: Text(n == 0
            ? 'The proxy is removed.'
            : 'The proxy is removed and switched off in $n ${n == 1 ? 'profile' : 'profiles'}. They will use your real IP address.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await proxy.delete(e.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: proxy,
      builder: (context, _) {
        final list = proxy.proxies;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Proxies'),
            actions: [
              IconButton(
                tooltip: 'Import a list',
                icon: const Icon(Icons.playlist_add),
                onPressed: () => _import(context),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context),
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.darkBase,
            icon: const Icon(Icons.add),
            label: const Text('Add proxy'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'A proxy changes the IP address websites see. Add proxies here once, then each profile '
                  'picks one in its own menu: Extensions > Proxy. You need a proxy server from a provider. '
                  'While a profile uses a proxy, WebRTC is switched off and downloads go through the proxy. '
                  'If the proxy does not work, pages do not load; your real IP address is not used instead.',
                  style: TextStyle(fontSize: 12, color: context.muted),
                ),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No proxies yet. Tap Add proxy.', textAlign: TextAlign.center),
                ),
              for (final e in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    color: context.panel,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Row(
                        children: [
                          const CircleAvatar(backgroundColor: AppColors.purple, child: Icon(Icons.vpn_key_outlined, color: Colors.white)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                Text(e.address, style: const TextStyle(fontSize: 13)),
                                Text(
                                  '${e.hasLogin ? 'With login' : 'No login'}  |  used by ${proxy.usage[e.id] ?? 0} '
                                  '${(proxy.usage[e.id] ?? 0) == 1 ? 'profile' : 'profiles'}',
                                  style: TextStyle(fontSize: 11, color: context.muted),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _edit(context, e);
                              if (v == 'delete') _delete(context, e);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ProxyInput {
  const _ProxyInput(this.name, this.scheme, this.host, this.port, this.username, this.password);
  final String name;
  final String scheme;
  final String host;
  final int port;
  final String username;
  final String password;
}

class _ProxyDialog extends StatefulWidget {
  const _ProxyDialog({this.existing});
  final ProxyEntry? existing;

  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _host = TextEditingController(text: widget.existing?.host ?? '');
  late final TextEditingController _port =
      TextEditingController(text: widget.existing == null ? '' : '${widget.existing!.port}');
  late final TextEditingController _user = TextEditingController(text: widget.existing?.username ?? '');
  final TextEditingController _pass = TextEditingController();
  late String _scheme = widget.existing?.scheme ?? 'http';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty || host.contains(' ') || host.contains('/') || host.contains(':')) {
      setState(() => _error = 'Enter the host only, for example proxy.example.com');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Enter a port from 1 to 65535');
      return;
    }
    final name = _name.text.trim().isEmpty ? host : _name.text.trim();
    Navigator.pop(context, _ProxyInput(name, _scheme, host, port, _user.text.trim(), _pass.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add proxy' : 'Edit proxy'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'http', label: Text('HTTP')),
                ButtonSegment(value: 'https', label: Text('HTTPS')),
                ButtonSegment(value: 'socks5', label: Text('SOCKS5')),
              ],
              selected: {_scheme},
              onSelectionChanged: (s) => setState(() => _scheme = s.first),
            ),
            const SizedBox(height: 8),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name (optional)')),
            TextField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Host', hintText: 'proxy.example.com'),
            ),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            ),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username (optional)')),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password (optional)',
                helperText: widget.existing?.hasLogin == true ? 'Leave empty to keep the current password' : null,
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.existing == null ? 'Add' : 'Save')),
      ],
    );
  }
}


class ParsedProxy {
  const ParsedProxy(this.scheme, this.host, this.port, this.user, this.pass);
  final String? scheme; // null = use the type chosen in the dialog
  final String host;
  final int port;
  final String user;
  final String pass;
}

/// Reads one proxy per line. Understood formats:
/// host:port:user:pass | user:pass@host:port | scheme://user:pass@host:port | host:port
/// Lines that cannot be read are added to [bad].
List<ParsedProxy> parseProxyList(String text, List<String> bad) {
  final out = <ParsedProxy>[];
  for (final raw in text.split(RegExp(r'[\r\n]+'))) {
    var s = raw.trim();
    if (s.isEmpty) continue;
    String? scheme;
    final m = RegExp(r'^(https?|socks5h?)://', caseSensitive: false).firstMatch(s);
    if (m != null) {
      final sc = m.group(1)!.toLowerCase();
      scheme = sc.startsWith('socks') ? 'socks5' : sc;
      s = s.substring(m.end());
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    String host = '';
    int? port;
    var user = '';
    var pass = '';
    if (s.contains('@')) {
      final at = s.lastIndexOf('@');
      final cred = s.substring(0, at);
      final addr = s.substring(at + 1).split(':');
      final ci = cred.indexOf(':');
      user = ci < 0 ? cred : cred.substring(0, ci);
      pass = ci < 0 ? '' : cred.substring(ci + 1);
      if (addr.length == 2) {
        host = addr[0];
        port = int.tryParse(addr[1]);
      }
    } else {
      final parts = s.split(':');
      if (parts.length == 2) {
        host = parts[0];
        port = int.tryParse(parts[1]);
      } else if (parts.length >= 4) {
        host = parts[0];
        port = int.tryParse(parts[1]);
        user = parts[2];
        pass = parts.sublist(3).join(':');
      }
    }
    if (host.isEmpty || host.contains(' ') || host.contains('/') || port == null || port < 1 || port > 65535) {
      bad.add(raw);
      continue;
    }
    out.add(ParsedProxy(scheme, host, port, user, pass));
  }
  return out;
}

class _ImportInput {
  const _ImportInput(this.text, this.scheme, this.prefix);
  final String text;
  final String scheme;
  final String prefix;
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _prefix = TextEditingController();
  String _scheme = 'http';

  @override
  void dispose() {
    _text.dispose();
    _prefix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import proxies'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste one proxy per line. Accepted: host:port:user:pass, user:pass@host:port, or host:port.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'http', label: Text('HTTP')),
                ButtonSegment(value: 'https', label: Text('HTTPS')),
                ButtonSegment(value: 'socks5', label: Text('SOCKS5')),
              ],
              selected: {_scheme},
              onSelectionChanged: (s) => setState(() => _scheme = s.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _prefix,
              decoration: const InputDecoration(labelText: 'Name prefix (optional)', hintText: 'Webshare'),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _text,
              minLines: 6,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: '203.0.113.5:8080:myuser:mypass',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ImportInput(_text.text, _scheme, _prefix.text.trim())),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
