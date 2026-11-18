import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/home_shortcut.dart';

class ShortcutInput {
  const ShortcutInput(this.url, this.title, this.pinned, this.image, this.allProfiles);
  final String url;
  final String title;
  final bool pinned;
  final Uint8List? image;
  final bool allProfiles;
}

/// Add or edit a Popular site (pass [existing] to edit).
Future<ShortcutInput?> showShortcutDialog(BuildContext context, {HomeShortcut? existing}) {
  return showDialog<ShortcutInput>(
    context: context,
    builder: (_) => _ShortcutDialog(existing: existing),
  );
}

class _ShortcutDialog extends StatefulWidget {
  const _ShortcutDialog({this.existing});
  final HomeShortcut? existing;

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _url = TextEditingController(text: widget.existing?.url ?? '');
  late bool _pinned = widget.existing?.pinned ?? false;
  late bool _all = widget.existing?.allProfiles ?? false;
  late Uint8List? _image = widget.existing?.image;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 85,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > 400000) {
        setState(() => _error = 'That image is too large. Choose a smaller one.');
        return;
      }
      setState(() {
        _image = bytes;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not load the image: $e');
    }
  }

  void _submit() {
    var u = _url.text.trim();
    if (u.isEmpty) {
      setState(() => _error = 'Enter an address');
      return;
    }
    final lower = u.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) u = 'https://$u';
    final host = Uri.tryParse(u)?.host ?? '';
    if (host.isEmpty || (!host.contains('.') && host != 'localhost')) {
      setState(() => _error = 'This is not a valid address');
      return;
    }
    var t = _title.text.trim();
    if (t.isEmpty) t = host;
    Navigator.pop(context, ShortcutInput(u, t, _pinned, _image, _all));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add to Popular' : 'Edit site'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: Colors.white12,
                    child: _image != null
                        ? Image.memory(_image!, fit: BoxFit.cover)
                        : const Icon(Icons.image_outlined),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(onPressed: _pick, child: const Text('Choose image')),
                      if (_image != null)
                        TextButton(
                          onPressed: () => setState(() => _image = null),
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: 'Address', errorText: _error),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pin to the top'),
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add to all profiles'),
              subtitle: const Text('Shown in the Shortcuts of every profile, also new ones. You can choose profiles later from the card menu.'),
              value: _all,
              onChanged: (v) => setState(() => _all = v),
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
