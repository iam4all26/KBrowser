import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/browser_tab.dart';

/// Tabs of ONE profile (persisted in SQLite).
class TabService extends ChangeNotifier {
  TabService(this._db, this.profileId);

  final Database _db;
  final String profileId;

  /// Set by the browser screen from the profile's search engine / defaults.
  String homeUrl = 'https://www.google.com';
  bool desktopDefault = false;

  List<BrowserTab> tabs = [];
  String? activeId;
  final List<BrowserTab> recentlyClosed = []; // this session only
  int _seq = 0;

  BrowserTab? get active {
    for (final t in tabs) {
      if (t.id == activeId) return t;
    }
    return null;
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;
  String _newId() => 'tab_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  Future<void> load() async {
    final rows = await _db.query(
      'tabs',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'position ASC',
    );
    tabs = rows.map(BrowserTab.fromMap).toList();
    if (tabs.isEmpty) {
      await addTab(url: homeUrl, desktop: desktopDefault, notify: false);
    }
    final marked = tabs.where((t) => t.isActive);
    activeId = marked.isNotEmpty ? marked.first.id : tabs.first.id;
  }

  Future<BrowserTab> addTab({
    required String url,
    required bool desktop,
    bool select = true,
    bool notify = true,
  }) async {
    final now = _now();
    var pos = 0;
    for (final t in tabs) {
      if (t.position >= pos) pos = t.position + 1;
    }
    final tab = BrowserTab(
      id: _newId(),
      profileId: profileId,
      url: url,
      title: '',
      position: pos,
      isActive: false,
      desktopMode: desktop,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert('tabs', tab.toMap());
    tabs = [...tabs, tab];
    if (select) {
      await _persistActive(tab.id);
    }
    if (notify) notifyListeners();
    return tab;
  }

  Future<void> _persistActive(String id) async {
    activeId = id;
    tabs = [for (final t in tabs) t.copyWith(isActive: t.id == id)];
    await _db.update('tabs', {'is_active': 0}, where: 'profile_id = ?', whereArgs: [profileId]);
    await _db.update('tabs', {'is_active': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> select(String id) async {
    if (id == activeId) return;
    await _persistActive(id);
    notifyListeners();
  }

  Future<void> close(String id) async {
    final index = tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final closed = tabs[index];
    if (closed.url.isNotEmpty) {
      recentlyClosed.add(closed);
      if (recentlyClosed.length > 10) recentlyClosed.removeAt(0);
    }
    await _db.delete('tabs', where: 'id = ?', whereArgs: [id]);
    tabs = [...tabs]..removeAt(index);
    if (tabs.isEmpty) {
      await addTab(url: homeUrl, desktop: desktopDefault, notify: false);
    } else if (activeId == id) {
      final next = tabs[index.clamp(0, tabs.length - 1)];
      await _persistActive(next.id);
    }
    notifyListeners();
  }

  Future<void> closeAll() async {
    for (final t in tabs) {
      if (t.url.isNotEmpty) recentlyClosed.add(t);
    }
    while (recentlyClosed.length > 10) {
      recentlyClosed.removeAt(0);
    }
    await _db.delete('tabs', where: 'profile_id = ?', whereArgs: [profileId]);
    tabs = [];
    await addTab(url: homeUrl, desktop: desktopDefault, notify: false);
    notifyListeners();
  }

  Future<void> reopenClosed() async {
    if (recentlyClosed.isEmpty) return;
    final t = recentlyClosed.removeLast();
    await addTab(url: t.url, desktop: t.desktopMode);
  }

  Future<void> duplicate(String id) async {
    for (final t in tabs) {
      if (t.id == id) {
        await addTab(url: t.url, desktop: t.desktopMode);
        return;
      }
    }
  }

  Future<void> updatePage(String id, String url, String title) async {
    final index = tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final old = tabs[index];
    if (old.url == url && old.title == title) return;
    final updated = old.copyWith(url: url, title: title, updatedAt: _now());
    tabs = [...tabs]..[index] = updated;
    notifyListeners();
    await _db.update(
      'tabs',
      {'url': url, 'title': title, 'updated_at': updated.updatedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setDesktop(String id, bool value) async {
    final index = tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    tabs = [...tabs]..[index] = tabs[index].copyWith(desktopMode: value, updatedAt: _now());
    notifyListeners();
    await _db.update(
      'tabs',
      {'desktop_mode': value ? 1 : 0, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
