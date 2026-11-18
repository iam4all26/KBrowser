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
          appBar: AppBar(title: const Text('Proxies')),
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
