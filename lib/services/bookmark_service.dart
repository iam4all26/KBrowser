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

  Future<void> removeUrl(String url) =>
      _db.delete('bookmarks', where: 'profile_id = ? AND url = ?', whereArgs: [profileId, url]);

  Future<void> delete(int id) =>
      _db.delete('bookmarks', where: 'id = ? AND profile_id = ?', whereArgs: [id, profileId]);
}
