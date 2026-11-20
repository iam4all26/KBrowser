import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/browser_tab.dart';
import '../../models/history_entry.dart';

/// Recent tabs of ONE profile: tabs closed in this session and the last pages visited.
Future<void> showRecentTabs(
  BuildContext context, {
  required List<BrowserTab> closed,
  required List<HistoryEntry> visited,
  required void Function(BrowserTab tab) onOpenClosed,
  required void Function(String url) onOpenUrl,
}) {
  String label(String title, String url) {
    if (title.trim().isNotEmpty) return title.trim();
    return Uri.tryParse(url)?.host.isNotEmpty == true ? Uri.parse(url).host : url;
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      Widget header(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(text, style: TextStyle(fontSize: 12, color: ctx.muted, fontWeight: FontWeight.w600)),
          );
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text('Recent tabs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              if (closed.isNotEmpty) header('Recently closed'),
              for (final t in closed)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.restore),
                  title: Text(label(t.title, t.url), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(t.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(ctx);
                    onOpenClosed(t);
                  },
                ),
              if (visited.isNotEmpty) header('Recently visited'),
              for (final h in visited)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history),
                  title: Text(label(h.title, h.url), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(h.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(ctx);
                    onOpenUrl(h.url);
                  },
                ),
              if (closed.isEmpty && visited.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Nothing here yet', style: TextStyle(color: ctx.muted)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
