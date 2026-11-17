import 'package:sqflite/sqflite.dart';

import '../models/history_entry.dart';

/// Browsing history of ONE profile (SQLite table `history`).
class HistoryService {
  HistoryService(this._db, this.profileId);

  final Database _db;
  final String profileId;

  static const int _sameVisitWindowMs = 5 * 60 * 1000;

  /// Records a finished page load. Only http and https pages are kept.
  /// Reloading the same address within 5 minutes updates the last entry.
  Future<void> record(String url, String title) async {
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = await _db.query(
      'history',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (last.isNotEmpty) {
      final row = last.first;
      final sameUrl = row['url'] == url;
      final recent = now - (row['visited_at'] as int) < _sameVisitWindowMs;
      if (sameUrl && recent) {
        if (title.isNotEmpty && title != row['title']) {
          await _db.update('history', {'title': title}, where: 'id = ?', whereArgs: [row['id']]);
        }
        return;
      }
    }
    await _db.insert('history', {
      'profile_id': profileId,
      'url': url,
      'title': title,
      'visited_at': now,
    });
  }

  Future<List<HistoryEntry>> list({String query = '', int limit = 500}) async {
    final q = query.trim();
    final rows = await _db.query(
      'history',
      where: q.isEmpty ? 'profile_id = ?' : 'profile_id = ? AND (title LIKE ? OR url LIKE ?)',
      whereArgs: q.isEmpty ? [profileId] : [profileId, '%$q%', '%$q%'],
      orderBy: 'visited_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(HistoryEntry.fromMap).toList();
  }

  Future<void> delete(int id) =>
      _db.delete('history', where: 'id = ? AND profile_id = ?', whereArgs: [id, profileId]);

  Future<void> clear() =>
      _db.delete('history', where: 'profile_id = ?', whereArgs: [profileId]);
}
