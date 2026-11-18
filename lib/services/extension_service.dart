import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../features/extensions/userscript.dart';
import '../models/user_extension.dart';

/// Extension library (app-wide, added at the main Home) and which profiles use which.
class ExtensionService extends ChangeNotifier {
  ExtensionService(this._db);

  final Database _db;
  List<UserExtension> extensions = const [];
  Map<int, int> usage = const {}; // extension id -> number of profiles using it

  Future<void> load() async {
    final rows = await _db.query('extensions', orderBy: 'created_at DESC, id DESC');
    extensions = rows.map(UserExtension.fromMap).toList();
    final u = await _db.rawQuery(
      'SELECT extension_id AS id, COUNT(*) AS c FROM profile_extensions WHERE enabled = 1 GROUP BY extension_id',
    );
    usage = {for (final r in u) r['id'] as int: r['c'] as int};
    notifyListeners();
  }

  Map<String, Object?> _values(ParsedUserscript p, String? sourceUrl) => {
        'name': p.name,
        'version': p.version,
        'description': p.description,
        'matches': p.matches.join('\n'),
        'excludes': p.excludes.join('\n'),
        'run_at': p.runAt,
        'code': p.code,
        'source_url': sourceUrl,
      };

  Future<int> add(ParsedUserscript p, {String? sourceUrl}) async {
    final id = await _db.insert('extensions', {
      ..._values(p, sourceUrl),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await load();
    return id;
  }

  /// Replaces the code of an installed extension (profiles keep it switched on).
  Future<void> replace(int id, ParsedUserscript p, {String? sourceUrl}) async {
    await _db.update('extensions', _values(p, sourceUrl), where: 'id = ?', whereArgs: [id]);
    await load();
  }

  Future<void> delete(int id) async {
    await _db.delete('profile_extensions', where: 'extension_id = ?', whereArgs: [id]);
    await _db.delete('extensions', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  Future<Set<int>> enabledFor(String profileId) async {
    final rows = await _db.query(
      'profile_extensions',
      columns: ['extension_id'],
      where: 'profile_id = ? AND enabled = 1',
      whereArgs: [profileId],
    );
    return {for (final r in rows) r['extension_id'] as int};
  }

  Future<void> setEnabled(String profileId, int extensionId, bool on) async {
    await _db.insert(
      'profile_extensions',
      {'profile_id': profileId, 'extension_id': extensionId, 'enabled': on ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await load();
  }

  /// Ready-to-inject scripts of the extensions switched on for [profileId].
  Future<List<String>> scriptsFor(String profileId) async {
    final rows = await _db.rawQuery(
      'SELECT e.* FROM extensions e JOIN profile_extensions p ON p.extension_id = e.id '
      'WHERE p.profile_id = ? AND p.enabled = 1 ORDER BY e.id',
      [profileId],
    );
    return rows.map((r) => buildInjectedScript(UserExtension.fromMap(r))).toList();
  }
}
