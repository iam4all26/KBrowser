import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Menu that drops down from the top-right, under the toolbar, and is at most
/// 72% of the screen high (it scrolls if there is more), narrow and compact like Chrome's menu. Use Navigator.pop(ctx)
/// with the context given to [builder] to close it.
Future<void> showTopMenu(BuildContext context, {required Widget Function(BuildContext ctx) builder}) {
  final media = MediaQuery.of(context);
  final width = media.size.width < 272 ? media.size.width - 16 : 256.0;
  final top = media.padding.top + 56;
  final maxHeight = (media.size.height * 0.72).clamp(0.0, media.size.height - top - media.padding.bottom - 12);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, a1, a2) => Stack(
      children: [
        Positioned(
          top: top,
          right: 8,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Material(
              elevation: 10,
              color: ctx.panel,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: MediaQuery.removePadding(
                context: ctx,
                removeTop: true,
                removeBottom: true,
                child: Theme(
                  data: Theme.of(ctx).copyWith(
                    listTileTheme: const ListTileThemeData(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      horizontalTitleGap: 12,
                      minLeadingWidth: 24,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                  child: SingleChildScrollView(child: builder(ctx)),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        alignment: Alignment.topRight,
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
}
