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
  }) async {
    if (await contains(url)) return false;
    await _db.insert('home_shortcuts', {
      'url': url,
      'title': title,
      'image': image,
      'pinned': pinned ? 1 : 0,
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
  }) async {
    await _db.update(
      'home_shortcuts',
      {'url': url, 'title': title, 'pinned': pinned ? 1 : 0, 'image': image},
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
    await _db.delete('home_shortcuts', where: 'id = ?', whereArgs: [id]);
    await load();
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
