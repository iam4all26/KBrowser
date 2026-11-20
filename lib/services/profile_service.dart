import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:kmulti_profiles/kmulti_profiles.dart';
import 'package:sqflite/sqflite.dart';

import '../features/browser/private_session.dart';

import '../models/app_profile.dart';

class CreateResult {
  const CreateResult(this.created, this.failed);
  final int created;
  final List<String> failed; // engine names that could not be created
}

class DeleteResult {
  const DeleteResult(this.deleted, this.failed, [this.pending = const {}]);
  final int deleted;
  final Map<String, String> failed; // id -> reason (the profile stays in the list)
  /// Removed from the list, but the browser engine refused to erase its data
  /// (a WebView was still using it). The data is erased at the next app start.
  final Map<String, String> pending; // id -> engine reason
}

/// Owns profile metadata (SQLite) and keeps it in step with the engine
/// profiles (AndroidX WebKit ProfileStore). There is no shared-storage fallback.
class ProfileService extends ChangeNotifier {
  ProfileService(this._db);

  final Database _db;
  static const int maxBatch = 100;
  static final RegExp _engineName = RegExp(r'^km_(\d+)$');
  static const List<String> defaultColors = [
    '#7351FF', '#F6C101', '#E5484D', '#30A46C',
    '#0091FF', '#F76B15', '#E93D82', '#12A594',
  ];

  Database get db => _db;

  List<AppProfile> profiles = const [];
  bool supported = false;
  String engineInfo = '';

  Future<void> init() async {
    final info = await KMultiProfiles.info();
    supported = info['supported'] == true;
    engineInfo = (info['webViewVersion'] ?? 'unknown').toString();
    if (supported) {
      await PrivateSession.cleanupLeftovers();
      await _wipePending();
      await _reconcile();
    }
    await _load();
  }

  Future<void> _load() async {
    final rows = await _db.query('profiles', orderBy: 'id ASC');
    profiles = rows.map(AppProfile.fromMap).toList();
    notifyListeners();
  }

  /// Adopts engine profiles that have no row (for example the Phase 0 test
  /// profiles, keeping their sessions) and re-creates engine profiles for rows
  /// whose engine profile is missing.
  Future<void> _reconcile() async {
    final engine = await KMultiProfiles.listProfiles();
    final rows = await _db.query('profiles');
    final known = rows.map((r) => r['engine_profile_name'] as String).toSet();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final name in engine) {
      final m = _engineName.firstMatch(name);
      if (m == null || known.contains(name)) continue;
      final n = int.parse(m.group(1)!);
      await _db.insert('profiles', _newRow(name, n, now));
    }
    for (final name in known) {
      if (!engine.contains(name)) {
        await KMultiProfiles.ensureProfile(name);
      }
    }
  }

  Map<String, Object?> _newRow(String id, int n, int now) {
    return AppProfile(
      id: id,
      engineProfileName: id,
      displayName: 'Profile $n',
      icon: 'person',
      color: defaultColors[(n - 1).abs() % defaultColors.length],
      createdAt: now,
      updatedAt: now,
    ).toMap();
  }

  Future<int> _nextNumber() async {
    var max = 0;
    for (final p in profiles) {
      if (p.number > max) max = p.number;
    }
    final engine = await KMultiProfiles.listProfiles();
    for (final name in engine) {
      final m = _engineName.firstMatch(name);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        if (n > max) max = n;
      }
    }
    return max + 1;
  }

  /// Creates [quantity] profiles one by one. A failure on one profile is
  /// cleaned up and reported without stopping the others.
  Future<CreateResult> createProfiles(int quantity) async {
    if (!supported) {
      throw StateError('Multi-Profile API is not supported on this device.');
    }
    if (quantity < 1 || quantity > maxBatch) {
      throw ArgumentError('Quantity must be between 1 and $maxBatch.');
    }
    var n = await _nextNumber();
    var created = 0;
    final failed = <String>[];
    for (var i = 0; i < quantity; i++, n++) {
      final id = 'km_${n.toString().padLeft(3, '0')}';
      var engineCreated = false;
      try {
        await KMultiProfiles.ensureProfile(id);
        engineCreated = true;
        final now = DateTime.now().millisecondsSinceEpoch;
        await _db.insert('profiles', _newRow(id, n, now));
        created++;
      } catch (_) {
        failed.add(id);
        if (engineCreated) {
          try {
            await KMultiProfiles.deleteProfile(id);
          } catch (_) {}
        }
      }
    }
    await _load();
    return CreateResult(created, failed);
  }

  Future<void> rename(String id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 40) {
      throw ArgumentError('Name must be 1 to 40 characters.');
    }
    await _db.update(
      'profiles',
      {'display_name': clean, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _load();
  }

  Future<void> setStyle(String id, {required String icon, required String color}) async {
    await _db.update(
      'profiles',
      {'icon': icon, 'color': color, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _load();
  }

  Future<String?> getSetting(String profileId, String key) async {
    final r = await _db.query(
      'profile_settings',
      where: 'profile_id = ? AND key = ?',
      whereArgs: [profileId, key],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setSetting(String profileId, String key, String value) async {
    await _db.insert(
      'profile_settings',
      {'profile_id': profileId, 'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> touchActive(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'profiles',
      {'last_active_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _load();
  }

  static String _short(Object e) => e is PlatformException ? (e.message ?? e.code) : e.toString();

  static const String _pendingKey = 'pending_wipe';

  Future<List<String>> _readPending() async {
    final r = await _db.query('app_settings', where: 'key = ?', whereArgs: [_pendingKey], limit: 1);
    if (r.isEmpty) return [];
    return ((r.first['value'] as String?) ?? '').split(',').where((s) => s.isNotEmpty).toList();
  }

  Future<void> _writePending(List<String> names) async {
    await _db.insert(
      'app_settings',
      {'key': _pendingKey, 'value': names.join(',')},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _addPending(String name) async {
    final list = await _readPending();
    if (!list.contains(name)) await _writePending([...list, name]);
  }

  /// At app start no WebView is alive, so engine profiles that could not be erased
  /// earlier can be erased now (before they could be re-adopted as profiles).
  Future<void> _wipePending() async {
    final list = await _readPending();
    if (list.isEmpty) return;
    final left = <String>[];
    for (final name in list) {
      try {
        await KMultiProfiles.deleteProfile(name);
      } catch (_) {
        left.add(name);
      }
    }
    await _writePending(left);
  }

  /// Deletes profiles. The engine can refuse while a WebView is still being closed,
  /// so it is tried several times. If it still refuses, the profile is removed from
  /// the list and its data is erased at the next app start (see [DeleteResult.pending]).
  Future<DeleteResult> deleteProfiles(List<String> ids) async {
    var deleted = 0;
    final failed = <String, String>{};
    final pending = <String, String>{};
    for (final id in ids) {
      var engineOk = false;
      String engineError = 'unknown';
      for (final wait in const [0, 400, 1000, 2500]) {
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
        try {
          await KMultiProfiles.deleteProfile(id);
          engineOk = true;
          break;
        } catch (e) {
          engineError = _short(e);
        }
      }
      try {
        if (!engineOk) {
          await _addPending(id);
          pending[id] = engineError;
        }
        await _db.delete('tabs', where: 'profile_id = ?', whereArgs: [id]);
        await _db.delete('history', where: 'profile_id = ?', whereArgs: [id]);
        await _db.delete('bookmarks', where: 'profile_id = ?', whereArgs: [id]);
        await _db.delete('profile_settings', where: 'profile_id = ?', whereArgs: [id]);
        await _db.delete('profile_extensions', where: 'profile_id = ?', whereArgs: [id]);
        await _db.delete('profile_shortcuts', where: 'profile_id = ?', whereArgs: [id]);
        await _db.delete('downloads', where: 'profile_id = ?', whereArgs: [id]);
        await _db.delete('passwords', where: 'profile_id = ?', whereArgs: [id]);
        await _db.delete('profiles', where: 'id = ?', whereArgs: [id]);
        deleted++;
      } catch (e) {
        pending.remove(id);
        failed[id] = _short(e);
      }
    }
    await _load();
    return DeleteResult(deleted, failed, pending);
  }
}
