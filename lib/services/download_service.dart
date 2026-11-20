import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/download_record.dart';

/// A download that is running (or has just failed). Kept in memory only.
class ActiveDownload {
  ActiveDownload({required this.id, required this.profileId, required this.name, required this.sourceUrl});
  final String id;
  final String profileId;
  String name;
  final String sourceUrl;
  int received = 0;
  int total = -1; // -1 = size not known
  int retry = 0;
  String? error; // set when the download failed

  bool get failed => error != null;

  /// 0.0 to 1.0, or null when the size is not known.
  double? get fraction => (total > 0) ? (received / total).clamp(0.0, 1.0).toDouble() : null;
}

/// Download records, kept per profile (the files themselves are on the phone), plus the
/// downloads that are running right now.
class DownloadService extends ChangeNotifier {
  DownloadService(this._db);
  final Database _db;

  final Map<String, ActiveDownload> _active = {};

  /// Running and just-failed downloads of [profileId], newest first.
  List<ActiveDownload> activeFor(String profileId) =>
      _active.values.where((a) => a.profileId == profileId).toList().reversed.toList();

  void started(String profileId, Map<String, dynamic> info) {
    final id = info['id'] as String?;
    if (id == null) return;
    _active[id] = ActiveDownload(
      id: id,
      profileId: profileId,
      name: (info['name'] as String?) ?? 'file',
      sourceUrl: (info['sourceUrl'] as String?) ?? '',
    );
    notifyListeners();
  }

  void progress(String profileId, Map<String, dynamic> info) {
    final id = info['id'] as String?;
    final a = id == null ? null : _active[id];
    if (a == null) return;
    final name = info['name'] as String?;
    if (name != null && name.isNotEmpty) a.name = name;
    a.received = (info['received'] as num?)?.toInt() ?? a.received;
    a.total = (info['total'] as num?)?.toInt() ?? a.total;
    a.retry = (info['retry'] as num?)?.toInt() ?? 0;
    notifyListeners();
  }

  void failed(Map<String, dynamic> info) {
    final id = info['id'] as String?;
    final a = id == null ? null : _active[id];
    if (a == null) return;
    a.error = (info['message'] as String?) ?? 'Download failed';
    notifyListeners();
  }

  /// Removes a failed entry from the list.
  void dismiss(String id) {
    if (_active.remove(id) != null) notifyListeners();
  }

  /// [info] is the event sent by the browser: id, name, location, isUri, mime, size, sourceUrl.
  Future<void> add(String profileId, Map<String, dynamic> info) async {
    final id = info['id'] as String?;
    if (id != null) _active.remove(id);
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
    _active.removeWhere((_, a) => a.profileId == profileId && a.failed);
    notifyListeners();
  }
}
