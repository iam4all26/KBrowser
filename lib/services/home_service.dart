import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/home_shortcut.dart';

class HomeStats {
  const HomeStats({
    required this.profiles,
    required this.tabs,
    required this.bookmarks,
    required this.history,
    required this.shortcuts,
    this.extensions = 0,
  });
  final int profiles;
  final int tabs;
  final int bookmarks;
  final int history;
  final int shortcuts;
  final int extensions;
}

/// App-wide Home data: the Popular sites and the stats shown above the profiles.
class HomeService extends ChangeNotifier {
  HomeService(this._db);

  final Database _db;
  List<HomeShortcut> shortcuts = const [];

  Future<void> load() async {
    final rows = await _db.query('home_shortcuts', orderBy: 'pinned DESC, created_at DESC, id DESC');
    shortcuts = rows.map(HomeShortcut.fromMap).toList();
    notifyListeners();
  }

  Future<bool> contains(String url) async {
    final r = await _db.query('home_shortcuts', columns: ['id'], where: 'url = ?', whereArgs: [url], limit: 1);
    return r.isNotEmpty;
  }

  /// Returns false if the address is already on Home.
  Future<bool> add({
    required String url,
    required String title,
    Uint8List? image,
    bool pinned = false,
    bool allProfiles = false,
  }) async {
    if (await contains(url)) return false;
    await _db.insert('home_shortcuts', {
      'url': url,
      'title': title,
      'image': image,
      'pinned': pinned ? 1 : 0,
      'all_profiles': allProfiles ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await load();
    return true;
  }

  Future<void> update(
    int id, {
    required String url,
    required String title,
    required bool pinned,
    Uint8List? image,
    bool? allProfiles,
  }) async {
    await _db.update(
      'home_shortcuts',
      {
        'url': url,
        'title': title,
        'pinned': pinned ? 1 : 0,
        'image': image,
        if (allProfiles != null) 'all_profiles': allProfiles ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await load();
  }

  Future<void> setPinned(int id, bool pinned) async {
    await _db.update('home_shortcuts', {'pinned': pinned ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    await load();
  }

  Future<void> delete(int id) async {
    await _db.delete('profile_shortcuts', where: 'shortcut_id = ?', whereArgs: [id]);
    await _db.delete('home_shortcuts', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  /// Popular sites shown in the start page Shortcuts of [profileId].
  Future<List<HomeShortcut>> forProfile(String profileId) async {
    final rows = await _db.rawQuery('''
SELECT s.id AS id, s.url AS url, s.title AS title, s.image AS image,
       COALESCE(l.pinned, s.pinned) AS pinned, s.created_at AS created_at,
       s.all_profiles AS all_profiles
FROM home_shortcuts s
LEFT JOIN profile_shortcuts l ON l.shortcut_id = s.id AND l.profile_id = ?
WHERE COALESCE(l.hidden, 0) = 0 AND (s.all_profiles = 1 OR l.profile_id IS NOT NULL)
ORDER BY COALESCE(l.pinned, s.pinned) DESC, s.created_at DESC, s.id DESC''', [profileId]);
    return rows.map(HomeShortcut.fromMap).toList();
  }

  Future<Set<String>> assignedProfiles(int shortcutId) async {
    final rows = await _db.query(
      'profile_shortcuts',
      columns: ['profile_id'],
      where: 'shortcut_id = ? AND hidden = 0',
      whereArgs: [shortcutId],
    );
    return {for (final r in rows) r['profile_id'] as String};
  }

  /// [all] shows the site in every profile (also new ones); otherwise only in [profileIds].
  Future<void> saveAssignment(int id, {required bool all, required Set<String> profileIds}) async {
    await _db.transaction((txn) async {
      await txn.update('home_shortcuts', {'all_profiles': all ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
      if (all) {
        await txn.update('profile_shortcuts', {'hidden': 0}, where: 'shortcut_id = ?', whereArgs: [id]);
      } else {
        if (profileIds.isEmpty) {
          await txn.delete('profile_shortcuts', where: 'shortcut_id = ?', whereArgs: [id]);
        } else {
          final marks = List.filled(profileIds.length, '?').join(',');
          await txn.delete(
            'profile_shortcuts',
            where: 'shortcut_id = ? AND profile_id NOT IN ($marks)',
            whereArgs: [id, ...profileIds],
          );
        }
        for (final pid in profileIds) {
          await txn.insert(
            'profile_shortcuts',
            {'profile_id': pid, 'shortcut_id': id, 'hidden': 0},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          await txn.update(
            'profile_shortcuts',
            {'hidden': 0},
            where: 'profile_id = ? AND shortcut_id = ?',
            whereArgs: [pid, id],
          );
        }
      }
    });
    await load();
  }

  /// Pin or unpin a site in ONE profile only.
  Future<void> setPinnedInProfile(String profileId, int shortcutId, bool pinned) async {
    await _db.insert(
      'profile_shortcuts',
      {'profile_id': profileId, 'shortcut_id': shortcutId, 'hidden': 0},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _db.update(
      'profile_shortcuts',
      {'pinned': pinned ? 1 : 0},
      where: 'profile_id = ? AND shortcut_id = ?',
      whereArgs: [profileId, shortcutId],
    );
  }

  /// Remove a site from ONE profile (it stays in Popular on the main Home).
  Future<void> removeFromProfile(String profileId, int shortcutId) async {
    final r = await _db.query('home_shortcuts', columns: ['all_profiles'], where: 'id = ?', whereArgs: [shortcutId], limit: 1);
    final all = r.isNotEmpty && (r.first['all_profiles'] as int? ?? 0) == 1;
    if (all) {
      await _db.insert(
        'profile_shortcuts',
        {'profile_id': profileId, 'shortcut_id': shortcutId, 'hidden': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await _db.update(
        'profile_shortcuts',
        {'hidden': 1},
        where: 'profile_id = ? AND shortcut_id = ?',
        whereArgs: [profileId, shortcutId],
      );
    } else {
      await _db.delete(
        'profile_shortcuts',
        where: 'profile_id = ? AND shortcut_id = ?',
        whereArgs: [profileId, shortcutId],
      );
    }
  }

  Future<int> _count(String table) async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<HomeStats> stats() async {
    return HomeStats(
      profiles: await _count('profiles'),
      tabs: await _count('tabs'),
      bookmarks: await _count('bookmarks'),
      history: await _count('history'),
      shortcuts: await _count('home_shortcuts'),
      extensions: await _count('extensions'),
    );
  }
}
