import 'package:flutter/material.dart';

import '../../models/app_profile.dart';
import '../../models/proxy_entry.dart';
import '../../models/user_extension.dart';
import '../../services/extension_service.dart';
import '../../services/proxy_service.dart';

/// Per-profile switches. Extensions and proxies can only be added from the main Home.
class ProfileExtensionsScreen extends StatefulWidget {
  const ProfileExtensionsScreen({
    super.key,
    required this.profile,
    required this.extensions,
    required this.proxy,
  });
  final AppProfile profile;
  final ExtensionService extensions;
  final ProxyService proxy;

  @override
  State<ProfileExtensionsScreen> createState() => _ProfileExtensionsScreenState();
}

class _ProfileExtensionsScreenState extends State<ProfileExtensionsScreen> {
  Set<int> _on = {};
  bool _adBlockOn = false;
  ProxyEntry? _proxy;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.extensions.load();
    await widget.proxy.load();
    final on = await widget.extensions.enabledFor(widget.profile.id);
    final ad = await widget.extensions.adBlockEnabledFor(widget.profile.id);
    final px = await widget.proxy.proxyFor(widget.profile.id);
    if (mounted) {
      setState(() {
        _on = on;
        _adBlockOn = ad;
        _proxy = px;
        _loaded = true;
      });
    }
  }

  Future<void> _toggleAdBlock(bool value) async {
    await widget.extensions.setAdBlockFor(widget.profile.id, value);
    if (mounted) setState(() => _adBlockOn = value);
  }

  Future<void> _pickProxy() async {
    final list = widget.proxy.proxies;
    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Proxy for this profile'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1),
            child: Row(
              children: [
                Icon(_proxy == null ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
                const SizedBox(width: 12),
                const Expanded(child: Text('None (my real IP address)')),
              ],
            ),
          ),
          for (final p in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.id),
              child: Row(
                children: [
                  Icon(_proxy?.id == p.id ? Icons.radio_button_checked : Icons.radio_button_off, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${p.name}  (${p.scheme}://${p.host}:${p.port})')),
                ],
              ),
            ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text('No proxies yet. Add them on the main Home, Extensions tab, Proxy.'),
            ),
        ],
      ),
    );
    if (choice == null) return;
    await widget.proxy.setProxyFor(widget.profile.id, choice < 0 ? null : choice);
    final px = await widget.proxy.proxyFor(widget.profile.id);
    if (mounted) setState(() => _proxy = px);
  }

  Future<void> _toggle(UserExtension e, bool value) async {
    if (value) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Turn on "${e.name}"?'),
          content: Text(
            'This extension can read and change the pages you open in ${widget.profile.displayName}, '
            'including what you type. Only turn it on if you trust where it came from.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn on')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await widget.extensions.setEnabled(widget.profile.id, e.id, value);
    if (mounted) {
      setState(() => value ? _on.add(e.id) : _on.remove(e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.extensions.extensions;
    final showAd = widget.extensions.adBlockAvailable;
    return Scaffold(
      appBar: AppBar(title: Text('Extensions: ${widget.profile.displayName}')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.vpn_key_outlined)),
                  title: const Text('Proxy'),
                  subtitle: Text(
                    _proxy == null
                        ? 'None. Websites see your real IP address.'
                        : '${_proxy!.name} (${_proxy!.scheme}://${_proxy!.host}:${_proxy!.port}). WebRTC is off and downloads use the proxy.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickProxy,
                ),
                const Divider(height: 1),
                if (showAd)
                  SwitchListTile(
                    secondary: const CircleAvatar(child: Icon(Icons.shield_outlined)),
                    title: const Text('Ad and tracker blocker'),
                    subtitle: const Text('Built-in. Blocks ad and tracker requests and hides empty ad boxes.'),
                    value: _adBlockOn,
                    onChanged: _toggleAdBlock,
                  ),
                for (final e in list)
                  SwitchListTile(
                    secondary: const CircleAvatar(child: Icon(Icons.extension_outlined)),
                    title: Text(e.version.isEmpty ? e.name : '${e.name}  ${e.version}'),
                    subtitle: Text(
                      e.description.isEmpty
                          ? (e.matches.isEmpty ? 'Runs on all sites' : 'Runs on: ${e.matches.take(2).join(', ')}')
                          : e.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: _on.contains(e.id),
                    onChanged: (v) => _toggle(e, v),
                  ),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No extensions yet. Extensions are added once from the main Home, in the Extensions tab. '
                      'Then you can switch them on here for this profile.',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }
}
