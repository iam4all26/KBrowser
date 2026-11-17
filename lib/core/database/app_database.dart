import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const _file = 'k_multi_browser.db';
  static const _version = 1;

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
      },
    );
  }
}
