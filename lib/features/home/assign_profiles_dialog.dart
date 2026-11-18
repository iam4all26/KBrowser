import 'package:flutter/material.dart';

import '../../models/app_profile.dart';
import '../../models/home_shortcut.dart';
import '../../services/home_service.dart';

class _Result {
  const _Result(this.all, this.ids);
  final bool all;
  final Set<String> ids;
}

/// Choose which profiles show a Popular site in their start page Shortcuts.
Future<void> showAssignProfilesDialog(
  BuildContext context, {
  required HomeService home,
  required HomeShortcut shortcut,
  required List<AppProfile> profiles,
}) async {
  final selected = await home.assignedProfiles(shortcut.id);
  if (!context.mounted) return;
  final list = [...profiles]..sort((a, b) => a.number.compareTo(b.number));
  final res = await showDialog<_Result>(
    context: context,
    builder: (_) => _AssignDialog(shortcut: shortcut, profiles: list, initialAll: shortcut.allProfiles, initial: selected),
  );
  if (res == null) return;
  await home.saveAssignment(shortcut.id, all: res.all, profileIds: res.ids);
}

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({
    required this.shortcut,
    required this.profiles,
    required this.initialAll,
    required this.initial,
  });
  final HomeShortcut shortcut;
  final List<AppProfile> profiles;
  final bool initialAll;
  final Set<String> initial;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  late bool _all = widget.initialAll;
  late final Set<String> _ids = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final title = widget.shortcut.title.isEmpty ? widget.shortcut.url : widget.shortcut.title;
    return AlertDialog(
      title: Text('Add "$title" to profiles'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All profiles'),
              subtitle: const Text('Also shown in profiles you create later'),
              value: _all,
              onChanged: (v) => setState(() => _all = v),
            ),
            const Divider(height: 1),
            Flexible(
              child: widget.profiles.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('No profiles yet.'))
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in widget.profiles)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.displayName),
                            value: _all || _ids.contains(p.id),
                            onChanged: _all
                                ? null
                                : (v) => setState(() => v == true ? _ids.add(p.id) : _ids.remove(p.id)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _Result(_all, _ids)), child: const Text('Save')),
      ],
    );
  }
}
