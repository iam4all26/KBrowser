import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_profile.dart';
import '../../models/browser_tab.dart';
import '../../services/tab_service.dart';
import '../profiles/profile_style.dart';
import 'url_utils.dart';

class TabSwitcherScreen extends StatelessWidget {
  const TabSwitcherScreen({super.key, required this.tabs, required this.profile});
  final TabService tabs;
  final AppProfile profile;

  /// Popped as the result when the profile chip is tapped.
  static const String switchProfile = 'switch_profile';

  String _title(BrowserTab t) {
    if (t.url.isEmpty || t.url == kHomeUrl) return 'New tab';
    if (t.title.isNotEmpty) return t.title;
    final host = Uri.tryParse(t.url)?.host ?? '';
    return host.isNotEmpty ? host : 'New tab';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tabs,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text('Tabs (${tabs.tabs.length})'),
            actions: [
              IconButton(
                tooltip: 'New tab',
                icon: const Icon(Icons.add),
                onPressed: () async {
                  await tabs.addTab(url: tabs.homeUrl, desktop: tabs.desktopDefault);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: CircleAvatar(
                      backgroundColor: ProfileStyle.colorFor(profile.color),
                      child: Icon(ProfileStyle.iconFor(profile.icon), size: 14, color: Colors.white),
                    ),
                    label: Text(profile.displayName),
                    onPressed: () => Navigator.pop(context, switchProfile),
                  ),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            itemCount: tabs.tabs.length,
            onReorder: (o, n) => tabs.move(o, n),
            itemBuilder: (_, i) {
              final t = tabs.tabs[i];
              final isActive = t.id == tabs.activeId;
              final title = _title(t);
              return Padding(
                key: ValueKey(t.id),
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Material(
                  color: context.panel,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      await tabs.select(t.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: context.faint,
                            child: Text(title.characters.first.toUpperCase()),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  t.url.isEmpty || t.url == kHomeUrl ? 'Start page' : t.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: context.muted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close tab',
                            icon: const Icon(Icons.close),
                            onPressed: () => tabs.close(t.id),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                              child: Icon(Icons.drag_handle, color: context.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Close All Tabs'),
                onPressed: () async {
                  await tabs.closeAll();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
