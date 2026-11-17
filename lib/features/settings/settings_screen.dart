import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';

/// App settings. For now: appearance (light, dark or system, and accent colour).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _section(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          t,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.muted),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          return ListView(
            children: [
              _section(context, 'Appearance'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => s.setThemeMode(v.first),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('System follows your phone setting.', style: TextStyle(fontSize: 12)),
              ),
              _section(context, 'Accent colour'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final e in AppSettings.accents.entries)
                      GestureDetector(
                        onTap: () => s.setAccent(e.key),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: e.key == s.accentId
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: e.key == s.accentId
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
