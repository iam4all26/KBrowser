import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/download_record.dart';

/// Download records, kept per profile (the files themselves are on the phone).
class DownloadService extends ChangeNotifier {
  DownloadService(this._db);
  final Database _db;

  /// [info] is the event sent by the browser: name, location, isUri, mime, size, sourceUrl.
  Future<void> add(String profileId, Map<String, dynamic> info) async {
    await _db.insert('downloads', {
      'profile_id': profileId,
      'name': (info['name'] as String?) ?? 'file',
      'location': (info['location'] as String?) ?? '',
      'is_uri': info['isUri'] == true ? 1 : 0,
      'mime': (info['mime'] as String?) ?? '',
      'size': (info['size'] as num?)?.toInt() ?? 0,
      'source_url': (info['sourceUrl'] as String?) ?? '',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
  }

  Future<List<DownloadRecord>> list(String profileId) async {
    final rows = await _db.query(
      'downloads',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(DownloadRecord.fromMap).toList();
  }

  Future<void> remove(int id) async {
    await _db.delete('downloads', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> clear(String profileId) async {
    await _db.delete('downloads', where: 'profile_id = ?', whereArgs: [profileId]);
    notifyListeners();
  }
}
