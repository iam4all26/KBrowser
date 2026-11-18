import 'package:flutter/foundation.dart';
import 'package:kmulti_profiles/kmulti_profiles.dart';
import 'package:sqflite/sqflite.dart';

import '../features/proxy/webrtc_script.dart';
import '../models/proxy_entry.dart';

/// Proxies (added once at the main Home) and which proxy each profile uses.
///
/// The WebView proxy is process-wide, so only ONE profile may have live WebViews
/// at a time: [applyFor] is called when a profile opens and the proxy is cleared
/// when it closes.
class ProxyService extends ChangeNotifier {
  ProxyService(this._db);

  /// Profile id that currently owns the process-wide proxy setting.
  static String? owner;

  final Database _db;
  List<ProxyEntry> proxies = const [];
  Map<int, int> usage = const {}; // proxy id -> number of profiles using it

  Future<void> load() async {
    final rows = await _db.query('proxies', orderBy: 'created_at DESC, id DESC');
    proxies = rows.map(ProxyEntry.fromMap).toList();
    final u = await _db.rawQuery(
      "SELECT value AS v, COUNT(*) AS c FROM profile_settings WHERE key = 'proxy_id' GROUP BY value",
    );
    final map = <int, int>{};
    for (final r in u) {
      final id = int.tryParse('${r['v']}');
      if (id != null) map[id] = r['c'] as int;
    }
    usage = map;
    notifyListeners();
  }

  Future<int> add({
    required String name,
    required String scheme,
    required String host,
    required int port,
    String username = '',
    String password = '',
  }) async {
    final enc = (username.isNotEmpty && password.isNotEmpty) ? await KMultiProfiles.encrypt(password) : '';
    final id = await _db.insert('proxies', {
      'name': name,
      'scheme': scheme,
      'host': host,
      'port': port,
      'username': username,
      'password_enc': enc,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await load();
    return id;
  }

  /// [password] null or empty keeps the stored password (unless the username is empty).
  Future<void> update(
    int id, {
    required String name,
    required String scheme,
    required String host,
    required int port,
    String username = '',
    String? password,
  }) async {
    final values = <String, Object?>{
      'name': name,
      'scheme': scheme,
      'host': host,
      'port': port,
      'username': username,
    };
    if (username.isEmpty) {
      values['password_enc'] = '';
    } else if (password != null && password.isNotEmpty) {
      values['password_enc'] = await KMultiProfiles.encrypt(password);
    }
    await _db.update('proxies', values, where: 'id = ?', whereArgs: [id]);
    await load();
  }

  /// Deleting a proxy switches it off in every profile that used it.
  Future<void> delete(int id) async {
    await _db.delete('profile_settings', where: "key = 'proxy_id' AND value = ?", whereArgs: ['$id']);
    await _db.delete('proxies', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  Future<ProxyEntry?> proxyFor(String profileId) async {
    final r = await _db.query(
      'profile_settings',
      where: "profile_id = ? AND key = 'proxy_id'",
      whereArgs: [profileId],
      limit: 1,
    );
    if (r.isEmpty) return null;
    final id = int.tryParse('${r.first['value']}');
    if (id == null) return null;
    final p = await _db.query('proxies', where: 'id = ?', whereArgs: [id], limit: 1);
    return p.isEmpty ? null : ProxyEntry.fromMap(p.first);
  }

  Future<void> setProxyFor(String profileId, int? proxyId) async {
    if (proxyId == null) {
      await _db.delete('profile_settings', where: "profile_id = ? AND key = 'proxy_id'", whereArgs: [profileId]);
    } else {
      await _db.insert(
        'profile_settings',
        {'profile_id': profileId, 'key': 'proxy_id', 'value': '$proxyId'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await load();
  }

  /// Applies this profile's proxy to the whole app (or clears it). Throws if the
  /// WebView cannot do it, so the caller must NOT open the profile in that case.
  Future<void> applyFor(String profileId) async {
    final p = await proxyFor(profileId);
    if (p == null) {
      await KMultiProfiles.clearProxy();
      return;
    }
    final password = p.passwordEnc.isEmpty ? '' : await KMultiProfiles.decrypt(p.passwordEnc);
    await KMultiProfiles.setProxy(
      scheme: p.scheme,
      host: p.host,
      port: p.port,
      username: p.username,
      password: password,
    );
  }

  /// Extra scripts for a profile: WebRTC is switched off while a proxy is used.
  Future<List<String>> guardScripts(String profileId) async {
    if (await proxyFor(profileId) == null) return const [];
    return [webRtcBlockScript];
  }
}
