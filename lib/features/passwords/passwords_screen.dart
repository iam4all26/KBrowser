import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_profile.dart';
import '../../services/password_service.dart';
import '../../services/profile_service.dart';

/// Saved logins of ONE profile, plus the "Save and fill passwords" switch.
class PasswordsScreen extends StatefulWidget {
  const PasswordsScreen({super.key, required this.profile, required this.passwords, required this.service});
  final AppProfile profile;
  final PasswordService passwords;
  final ProfileService service;

  @override
  State<PasswordsScreen> createState() => _PasswordsScreenState();
}

class _PasswordsScreenState extends State<PasswordsScreen> {
  final TextEditingController _search = TextEditingController();
  List<SavedLogin> _items = const [];
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final on = (await widget.service.getSetting(widget.profile.id, 'pw_enabled')) != '0';
    final items = await widget.passwords.all(query: _search.text);
    if (!mounted) return;
    setState(() {
      _enabled = on;
      _items = items;
      _loading = false;
    });
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _show(SavedLogin l) async {
    String? pw;
    var visible = false;
    try {
      pw = await widget.passwords.reveal(l.id);
    } catch (e) {
      _toast('Could not read the password: $e');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(l.host),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Username', style: TextStyle(fontSize: 12, color: ctx.muted)),
              SelectableText(l.username.isEmpty ? '(none)' : l.username),
              const SizedBox(height: 12),
              Text('Password', style: TextStyle(fontSize: 12, color: ctx.muted)),
              Row(
                children: [
                  Expanded(child: Text(visible ? pw! : '•' * 10)),
                  IconButton(
                    tooltip: visible ? 'Hide' : 'Show',
                    icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setS(() => visible = !visible),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: l.username));
                _toast('Username copied');
              },
              child: const Text('Copy username'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: pw!));
                _toast('Password copied');
              },
              child: const Text('Copy password'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(SavedLogin l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this login?'),
        content: Text('${l.username.isEmpty ? '(no username)' : l.username} on ${l.host}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.passwords.delete(l.id);
    await _load();
  }

  Future<void> _removeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all saved passwords?'),
        content: Text('Only for profile ${widget.profile.displayName}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete all')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.passwords.deleteAll();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Passwords: ${widget.profile.displayName}'),
        actions: [
          IconButton(
            tooltip: 'Delete all',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _items.isEmpty ? null : _removeAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SwitchListTile(
                  value: _enabled,
                  title: const Text('Save and fill passwords'),
                  subtitle: const Text('Asks before saving. Fills only when you tap Fill.'),
                  onChanged: (v) async {
                    await widget.service.setSetting(widget.profile.id, 'pw_enabled', v ? '1' : '0');
                    setState(() => _enabled = v);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search sites and usernames',
                      isDense: true,
                    ),
                    onChanged: (_) => _load(),
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? Center(child: Text('No saved passwords', style: TextStyle(color: context.muted)))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final l = _items[i];
                            return ListTile(
                              leading: const Icon(Icons.key_outlined),
                              title: Text(l.host),
                              subtitle: Text(l.username.isEmpty ? '(no username)' : l.username),
                              trailing: IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _remove(l),
                              ),
                              onTap: () => _show(l),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
