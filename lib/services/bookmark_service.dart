import 'package:sqflite/sqflite.dart';

import '../models/bookmark.dart';

/// Bookmarks of ONE profile (SQLite table `bookmarks`).
class BookmarkService {
  BookmarkService(this._db, this.profileId);

  final Database _db;
  final String profileId;

  Future<List<Bookmark>> list({String query = ''}) async {
    final q = query.trim();
    final rows = await _db.query(
      'bookmarks',
      where: q.isEmpty ? 'profile_id = ?' : 'profile_id = ? AND (title LIKE ? OR url LIKE ?)',
      whereArgs: q.isEmpty ? [profileId] : [profileId, '%$q%', '%$q%'],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<bool> contains(String url) async {
    final rows = await _db.query(
      'bookmarks',
      columns: ['id'],
      where: 'profile_id = ? AND url = ?',
      whereArgs: [profileId, url],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> add(String url, String title) async {
    if (await contains(url)) return;
    await _db.insert('bookmarks', {
      'profile_id': profileId,
      'url': url,
      'title': title,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Adds the bookmark to every profile in [profileIds] that does not have it yet.
  /// Returns how many profiles got it.
  static Future<int> addToAll(
    Database db,
    Iterable<String> profileIds,
    String url,
    String title,
  ) async {
    final rows = await db.query(
      'bookmarks',
      columns: ['profile_id'],
      where: 'url = ?',
      whereArgs: [url],
    );
    final have = rows.map((r) => r['profile_id'] as String).toSet();
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    var added = 0;
    for (final id in profileIds) {
      if (have.contains(id)) continue;
      batch.insert('bookmarks', {'profile_id': id, 'url': url, 'title': title, 'created_at': now});
      added++;
    }
    await batch.commit(noResult: true);
    return added;
  }

  Future<void> removeUrl(String url) =>
      _db.delete('bookmarks', where: 'profile_id = ? AND url = ?', whereArgs: [profileId, url]);

  Future<void> delete(int id) =>
      _db.delete('bookmarks', where: 'id = ? AND profile_id = ?', whereArgs: [id, profileId]);
}
