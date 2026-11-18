import 'package:flutter/material.dart';

import '../../models/app_profile.dart';
import '../../models/user_extension.dart';
import '../../services/extension_service.dart';

/// Per-profile switches. Extensions can only be added from the main Home.
class ProfileExtensionsScreen extends StatefulWidget {
  const ProfileExtensionsScreen({super.key, required this.profile, required this.extensions});
  final AppProfile profile;
  final ExtensionService extensions;

  @override
  State<ProfileExtensionsScreen> createState() => _ProfileExtensionsScreenState();
}

class _ProfileExtensionsScreenState extends State<ProfileExtensionsScreen> {
  Set<int> _on = {};
  bool _adBlockOn = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.extensions.load();
    final on = await widget.extensions.enabledFor(widget.profile.id);
    final ad = await widget.extensions.adBlockEnabledFor(widget.profile.id);
    if (mounted) {
      setState(() {
        _on = on;
        _adBlockOn = ad;
        _loaded = true;
      });
    }
  }

  Future<void> _toggleAdBlock(bool value) async {
    await widget.extensions.setAdBlockFor(widget.profile.id, value);
    if (mounted) setState(() => _adBlockOn = value);
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
          : (list.isEmpty && !showAd)
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No extensions yet. Extensions are added once from the main Home, in the Extensions tab. '
                      'Then you can switch them on here for this profile.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
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
                  ],
                ),
    );
  }
}
