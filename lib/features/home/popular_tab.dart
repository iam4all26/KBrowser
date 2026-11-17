import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/home_shortcut.dart';
import '../../services/home_service.dart';
import '../profiles/profile_style.dart';
import 'shortcut_dialog.dart';

/// Popular sites of the main Home. Tapping one asks which profile should open it.
class PopularTab extends StatelessWidget {
  const PopularTab({
    super.key,
    required this.home,
    required this.onOpen,
    required this.onToast,
  });

  final HomeService home;
  final void Function(HomeShortcut shortcut) onOpen;
  final void Function(String message) onToast;

  Future<void> _edit(BuildContext context, HomeShortcut s) async {
    final r = await showShortcutDialog(context, existing: s);
    if (r == null) return;
    await home.update(s.id, url: r.url, title: r.title, pinned: r.pinned, image: r.image);
  }

  Future<void> _delete(BuildContext context, HomeShortcut s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${s.title}"?'),
        content: const Text('It is removed from Popular. Profile bookmarks are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await home.delete(s.id);
  }

  Color _colorFor(String text) {
    final i = text.codeUnits.fold<int>(0, (a, b) => a + b) % ProfileStyle.colors.length;
    return ProfileStyle.colorFor(ProfileStyle.colors[i]);
  }

  Widget _card(BuildContext context, HomeShortcut s) {
    final label = s.title.isEmpty ? s.url : s.title;
    final color = _colorFor(s.url);
    return Material(
      color: context.panel,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(s),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: s.image != null
                          ? Image.memory(s.image!, fit: BoxFit.cover)
                          : Container(
                              color: color,
                              alignment: Alignment.center,
                              child: Text(
                                label.characters.first.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Uri.tryParse(s.url)?.host ?? s.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: context.muted),
                  ),
                ],
              ),
            ),
            if (s.pinned)
              const Positioned(top: 8, left: 8, child: Icon(Icons.push_pin, size: 16, color: AppColors.gold)),
            Positioned(
              top: 4,
              right: 0,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 20,
                onSelected: (v) {
                  switch (v) {
                    case 'open':
                      onOpen(s);
                    case 'pin':
                      home.setPinned(s.id, !s.pinned);
                    case 'edit':
                      _edit(context, s);
                    case 'delete':
                      _delete(context, s);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'open', child: Text('Open in a profile')),
                  PopupMenuItem(value: 'pin', child: Text(s.pinned ? 'Unpin' : 'Pin to top')),
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Remove')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: home,
      builder: (context, _) {
        final list = home.shortcuts;
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No popular sites yet. Tap Add site, or turn on "Add to Home" when you bookmark a page.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 130,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.9,
          ),
          itemCount: list.length,
          itemBuilder: (_, i) => _card(context, list[i]),
        );
      },
    );
  }
}
