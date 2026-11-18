import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Menu that drops down from the top-right, under the toolbar, and is at most
/// half of the screen high (it scrolls if there is more). Use Navigator.pop(ctx)
/// with the context given to [builder] to close it.
Future<void> showTopMenu(BuildContext context, {required Widget Function(BuildContext ctx) builder}) {
  final media = MediaQuery.of(context);
  final width = media.size.width < 332 ? media.size.width - 16 : 316.0;
  final top = media.padding.top + 56;
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
            constraints: BoxConstraints(maxHeight: media.size.height * 0.5),
            child: Material(
              elevation: 10,
              color: ctx.panel,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: MediaQuery.removePadding(
                context: ctx,
                removeTop: true,
                removeBottom: true,
                child: SingleChildScrollView(child: builder(ctx)),
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
