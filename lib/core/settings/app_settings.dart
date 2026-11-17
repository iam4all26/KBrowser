import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../theme/app_theme.dart';

/// App-wide settings (not per profile), stored in the `app_settings` table.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// Accent colour choices. The first one is the brand colour.
  static const Map<String, Color> accents = {
    'purple': AppColors.purple,
    'blue': Color(0xFF0091FF),
    'green': Color(0xFF30A46C),
    'teal': Color(0xFF12A594),
    'orange': Color(0xFFF76B15),
    'pink': Color(0xFFE93D82),
    'red': Color(0xFFE5484D),
  };

  ThemeMode themeMode = ThemeMode.dark;
  String accentId = 'purple';
  Database? _db;

  Color get accent => accents[accentId] ?? AppColors.purple;

  Future<void> load(Database db) async {
    _db = db;
    final rows = await db.query('app_settings');
    for (final r in rows) {
      final k = r['key'];
      final v = r['value'] as String?;
      if (v == null) continue;
      if (k == 'theme_mode') {
        for (final m in ThemeMode.values) {
          if (m.name == v) themeMode = m;
        }
      } else if (k == 'accent' && accents.containsKey(v)) {
        accentId = v;
      }
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _save('theme_mode', mode.name);
  }

  Future<void> setAccent(String id) async {
    if (!accents.containsKey(id)) return;
    accentId = id;
    notifyListeners();
    await _save('accent', id);
  }

  Future<void> _save(String key, String value) async {
    await _db?.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
