import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const _file = 'k_multi_browser.db';
  static const _version = 2;

  static Future<Database> open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      '$dir/$_file',
      version: _version,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE profiles (
    id TEXT PRIMARY KEY,
    engine_profile_name TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    icon TEXT,
    color TEXT,
    is_default INTEGER DEFAULT 0,
    is_locked INTEGER DEFAULT 0,
    is_active INTEGER DEFAULT 0,
    desktop_mode INTEGER DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_active_at INTEGER
)''');
        await _createV2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createV2(db);
      },
    );
  }

  /// Version 2: tabs and per-profile settings.
  static Future<void> _createV2(Database db) async {
    await db.execute('''
CREATE TABLE tabs (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL,
    url TEXT NOT NULL DEFAULT '',
    title TEXT NOT NULL DEFAULT '',
    position INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 0,
    desktop_mode INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
)''');
    await db.execute('CREATE INDEX idx_tabs_profile ON tabs (profile_id, position)');
    await db.execute('''
CREATE TABLE profile_settings (
    profile_id TEXT NOT NULL,
    key TEXT NOT NULL,
    value TEXT,
    PRIMARY KEY (profile_id, key)
)''');
  }
}
