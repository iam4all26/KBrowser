import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_profile.dart';
import '../../services/home_service.dart';
import '../profiles/profile_style.dart';

/// Small dashboard above the profile list.
class HomeStatsStrip extends StatelessWidget {
  const HomeStatsStrip({super.key, required this.stats, required this.profiles});
  final HomeStats? stats;
  final List<AppProfile> profiles;

  Widget _tile(BuildContext context, IconData icon, String label, int? value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value == null ? '-' : '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: context.muted)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppProfile? recent;
    for (final p in profiles) {
      if (p.lastActiveAt == null) continue;
      if (recent == null || p.lastActiveAt! > recent.lastActiveAt!) recent = p;
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: context.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _tile(context, Icons.people_outline, 'Profiles', stats?.profiles),
              _tile(context, Icons.tab_outlined, 'Open tabs', stats?.tabs),
              _tile(context, Icons.star_outline, 'Bookmarks', stats?.bookmarks),
              _tile(context, Icons.history, 'History', stats?.history),
            ],
          ),
          if (recent != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last used: ${recent.displayName}, ${ProfileStyle.lastActiveShort(recent.lastActiveAt).toLowerCase()}',
              style: TextStyle(fontSize: 11, color: context.muted),
            ),
          ],
        ],
      ),
    );
  }
}
