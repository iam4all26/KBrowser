import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const _file = 'k_multi_browser.db';
  static const _version = 9;

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
        await _createV3(db);
        await _createV4(db);
        await _createV5(db);
        await _createV6(db);
        await _createV7(db);
        await _createV8(db);
        await _createV9(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createV2(db);
        if (oldVersion < 3) {
          await _createV3(db);
          // Phase 1 profiles got 'person' only as an automatic default.
          await db.execute("UPDATE profiles SET icon = 'public' WHERE icon = 'person'");
        }
        if (oldVersion < 4) {
          await _createV4(db);
          // The person icon is the default again (batch 6).
          await db.execute("UPDATE profiles SET icon = 'person' WHERE icon = 'public'");
        }
        if (oldVersion < 5) await _createV5(db);
        if (oldVersion < 6) await _createV6(db);
        if (oldVersion < 7) await _createV7(db);
        if (oldVersion < 8) await _createV8(db);
        if (oldVersion < 9) await _createV9(db);
      },
    );
  }

  /// Version 9: proxies added at the main Home (password stored encrypted).
  /// The profile's choice lives in profile_settings, key 'proxy_id'.
  static Future<void> _createV9(Database db) async {
    await db.execute('''
CREATE TABLE proxies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    scheme TEXT NOT NULL,
    host TEXT NOT NULL,
    port INTEGER NOT NULL,
    username TEXT NOT NULL DEFAULT '',
    password_enc TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL
)''');
  }

  /// Version 8: Popular sites can be shown in the start page Shortcuts of profiles.
  /// profile_shortcuts: per-profile link (pinned overrides the Home pin, hidden removes
  /// an "all profiles" site from one profile).
  static Future<void> _createV8(Database db) async {
    await db.execute('ALTER TABLE home_shortcuts ADD COLUMN all_profiles INTEGER NOT NULL DEFAULT 0');
    await db.execute('''
CREATE TABLE profile_shortcuts (
    profile_id TEXT NOT NULL,
    shortcut_id INTEGER NOT NULL,
    pinned INTEGER,
    hidden INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (profile_id, shortcut_id)
)''');
  }

  /// Version 7: extensions (library added at the main Home) and per-profile switches.
  static Future<void> _createV7(Database db) async {
    await db.execute('''
CREATE TABLE extensions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    version TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    matches TEXT NOT NULL DEFAULT '',
    excludes TEXT NOT NULL DEFAULT '',
    run_at TEXT NOT NULL DEFAULT 'document-idle',
    code TEXT NOT NULL,
    source_url TEXT,
    created_at INTEGER NOT NULL
)''');
    await db.execute('''
CREATE TABLE profile_extensions (
    profile_id TEXT NOT NULL,
    extension_id INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (profile_id, extension_id)
)''');
  }

  /// Version 6: Popular sites on the main Home (app-wide, not per profile).
  static Future<void> _createV6(Database db) async {
    await db.execute('''
CREATE TABLE home_shortcuts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    url TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL DEFAULT '',
    image BLOB,
    pinned INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
)''');
  }

  /// Version 5: app-wide settings (theme mode, accent colour).
  static Future<void> _createV5(Database db) async {
    await db.execute('CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)');
  }

  /// Version 4: bookmarks, one list per profile.
  static Future<void> _createV4(Database db) async {
    await db.execute('''
CREATE TABLE bookmarks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id TEXT NOT NULL,
    url TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL
)''');
    await db.execute('CREATE INDEX idx_bookmarks_profile ON bookmarks (profile_id, created_at)');
  }

  /// Version 3: browsing history, one list per profile.
  static Future<void> _createV3(Database db) async {
    await db.execute('''
CREATE TABLE history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id TEXT NOT NULL,
    url TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    visited_at INTEGER NOT NULL
)''');
    await db.execute('CREATE INDEX idx_history_profile ON history (profile_id, visited_at)');
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
