import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// "Delete browsing data" for ONE profile. Returns the chosen parts:
/// 'history', 'cookies' (cookies and site storage), 'cache' and 'passwords', or null if cancelled.
Future<Set<String>?> showClearDataDialog(BuildContext context, {required String profileName}) {
  var history = true;
  var cookies = false;
  var cache = true;
  var passwords = false;
  return showDialog<Set<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Delete browsing data'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Only for profile: $profileName', style: TextStyle(fontSize: 12, color: ctx.muted)),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: history,
                onChanged: (v) => setState(() => history = v ?? false),
                title: const Text('Browsing history'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: cookies,
                onChanged: (v) => setState(() => cookies = v ?? false),
                title: const Text('Cookies and site data'),
                subtitle: const Text('Signs you out of sites in this profile'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: cache,
                onChanged: (v) => setState(() => cache = v ?? false),
                title: const Text('Cached images and files'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: passwords,
                onChanged: (v) => setState(() => passwords = v ?? false),
                title: const Text('Saved passwords'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: (history || cookies || cache || passwords)
                ? () => Navigator.pop(ctx, <String>{
                      if (history) 'history',
                      if (cookies) 'cookies',
                      if (cache) 'cache',
                      if (passwords) 'passwords',
                    })
                : null,
            child: const Text('Delete'),
          ),
        ],
      ),
    ),
  );
}
