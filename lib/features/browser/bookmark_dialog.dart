import 'package:flutter/material.dart';

class BookmarkInput {
  const BookmarkInput(this.url, this.title, this.allProfiles);
  final String url;
  final String title;
  final bool allProfiles;
}

/// Asks for a bookmark name and address, and whether to add it to every profile.
Future<BookmarkInput?> showBookmarkDialog(
  BuildContext context, {
  required String url,
  required String title,
  required bool editableUrl,
}) {
  return showDialog<BookmarkInput>(
    context: context,
    builder: (_) => _BookmarkDialog(url: url, title: title, editableUrl: editableUrl),
  );
}

class _BookmarkDialog extends StatefulWidget {
  const _BookmarkDialog({required this.url, required this.title, required this.editableUrl});
  final String url;
  final String title;
  final bool editableUrl;

  @override
  State<_BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<_BookmarkDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.title);
  late final TextEditingController _url = TextEditingController(text: widget.url);
  bool _all = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
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
    Navigator.pop(context, BookmarkInput(u, t, _all));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add bookmark'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _url,
              enabled: widget.editableUrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: 'Address', errorText: _error),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add to all profiles'),
              subtitle: const Text('Every existing profile gets this bookmark. Profiles created later start empty.'),
              value: _all,
              onChanged: (v) => setState(() => _all = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
