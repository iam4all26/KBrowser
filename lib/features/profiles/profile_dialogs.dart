import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/profile_service.dart';
import 'profile_style.dart';

/// Returns the requested quantity, or null if cancelled.
Future<int?> showCreateProfilesDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (_) => const _CreateDialog(),
  );
}

class _CreateDialog extends StatefulWidget {
  const _CreateDialog();

  @override
  State<_CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<_CreateDialog> {
  final _ctl = TextEditingController(text: '1');
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _bump(int delta) {
    final v = int.tryParse(_ctl.text) ?? 0;
    final next = (v + delta).clamp(1, ProfileService.maxBatch);
    setState(() {
      _ctl.text = '$next';
      _error = null;
    });
  }

  void _submit() {
    final v = int.tryParse(_ctl.text.trim());
    if (v == null || v < 1 || v > ProfileService.maxBatch) {
      setState(() => _error = 'Enter a number from 1 to ${ProfileService.maxBatch}');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create profiles'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How many profiles do you want? They are numbered automatically and can be renamed later.'),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton.outlined(onPressed: () => _bump(-1), icon: const Icon(Icons.remove)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _ctl,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(onPressed: () => _bump(1), icon: const Icon(Icons.add)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

Future<String?> showRenameDialog(BuildContext context, String current) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(current: current),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});
  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _ctl = TextEditingController(text: widget.current);
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctl.text.trim();
    if (t.isEmpty || t.length > 40) {
      setState(() => _error = 'Use 1 to 40 characters');
      return;
    }
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename profile'),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        maxLength: 40,
        decoration: InputDecoration(errorText: _error, border: const OutlineInputBorder()),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class StylePick {
  const StylePick(this.icon, this.color);
  final String icon;
  final String color;
}

Future<StylePick?> showAppearanceDialog(
  BuildContext context, {
  required String icon,
  required String color,
}) {
  return showDialog<StylePick>(
    context: context,
    builder: (_) => _AppearanceDialog(icon: icon, color: color),
  );
}

class _AppearanceDialog extends StatefulWidget {
  const _AppearanceDialog({required this.icon, required this.color});
  final String icon;
  final String color;

  @override
  State<_AppearanceDialog> createState() => _AppearanceDialogState();
}

class _AppearanceDialogState extends State<_AppearanceDialog> {
  late String _icon = ProfileStyle.icons.containsKey(widget.icon) ? widget.icon : 'public';
  late String _color = widget.color;

  @override
  Widget build(BuildContext context) {
    final selectedColor = ProfileStyle.colorFor(_color);
    return AlertDialog(
      title: const Text('Profile appearance'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Colour'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in ProfileStyle.colors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: ProfileStyle.colorFor(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _color ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Icon'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in ProfileStyle.icons.entries)
                  GestureDetector(
                    onTap: () => setState(() => _icon = e.key),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: e.key == _icon ? selectedColor : Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(e.value, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, StylePick(_icon, _color)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

Future<bool> confirmDelete(BuildContext context, int count, String firstName) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(count == 1 ? 'Delete "$firstName"?' : 'Delete $count profiles?'),
      content: const Text(
        'Logins, cookies, site data and saved data for the selected '
        'profile(s) are permanently removed. This cannot be undone.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return r == true;
}
