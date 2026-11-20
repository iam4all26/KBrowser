import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kmulti_profiles/kmulti_profiles.dart';
import 'package:sqflite/sqflite.dart';

import '../features/proxy/webrtc_script.dart';
import '../models/proxy_entry.dart';

/// Where a proxy exits to the internet (looked up through the proxy).
class ProxyGeo {
  const ProxyGeo({required this.ip, required this.country, required this.code});
  final String ip;
  final String country;
  final String code;

  String toStorage() => jsonEncode({'ip': ip, 'country': country, 'code': code});

  static ProxyGeo? fromStorage(String? v) {
    if (v == null || v.isEmpty) return null;
    try {
      final m = jsonDecode(v) as Map<String, dynamic>;
      final code = (m['code'] as String?) ?? '';
      if (code.length != 2) return null;
      return ProxyGeo(ip: (m['ip'] as String?) ?? '', country: (m['country'] as String?) ?? '', code: code);
    } catch (_) {
      return null;
    }
  }

  /// Flag made from the two-letter country code (empty if the code is invalid).
  String get flag {
    final u = code.toUpperCase().codeUnits;
    if (u.length != 2 || u.any((c) => c < 65 || c > 90)) return '';
    return String.fromCharCodes(u.map((c) => 0x1F1E6 + c - 65));
  }
}

/// Proxies (added once at the main Home) and which proxy each profile uses.
///
/// The WebView proxy is process-wide, so only ONE profile may have live WebViews
/// at a time: [applyFor] is called when a profile opens and the proxy is cleared
/// when it closes.
class ProxyService extends ChangeNotifier {
  ProxyService(this._db);

  /// Profile id that currently owns the process-wide proxy setting.
  static String? owner;

  static final Map<int, ProxyGeo> _geoCache = {};
  static ProxyGeo? _directGeo; // the phone's own connection, this session only
  final Set<int> _geoBusy = {};

  /// Where proxy [proxyId] exits, if known (memory or the saved copy). No network.
  ProxyGeo? cachedGeo(int proxyId) => _geoCache[proxyId];

  /// True while a lookup for [proxyId] is running (see [fillGeos]).
  bool isGeoBusy(int proxyId) => _geoBusy.contains(proxyId);

  Future<void> _saveGeo(int proxyId, ProxyGeo g) async {
    _geoCache[proxyId] = g;
    try {
      await _db.insert(
        'app_settings',
        {'key': 'proxy_geo_$proxyId', 'value': g.toStorage()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> _forgetGeo(int proxyId) async {
    _geoCache.remove(proxyId);
    try {
      await _db.delete('app_settings', where: 'key = ?', whereArgs: ['proxy_geo_$proxyId']);
    } catch (_) {}
  }

  ProxyGeo? _fromMap(Map<String, String>? m) =>
      m == null ? null : ProxyGeo(ip: m['ip'] ?? '', country: m['country'] ?? '', code: m['code'] ?? '');

  /// Country of proxy [proxyId]. It must already be applied to the app (applyFor).
  /// Cached per proxy; [refresh] asks again. If the lookup fails the last saved answer is kept.
  Future<ProxyGeo?> geoFor(int proxyId, {bool refresh = false}) async {
    if (!refresh && _geoCache.containsKey(proxyId)) return _geoCache[proxyId];
    final g = _fromMap(await KMultiProfiles.proxyGeo());
    if (g == null) return _geoCache[proxyId];
    await _saveGeo(proxyId, g);
    return g;
  }

  /// Country of the phone's own connection (used when the profile has no proxy).
  /// Only valid while no proxy is applied. Cached for the session; [refresh] asks again.
  Future<ProxyGeo?> directGeoFor({bool refresh = false}) async {
    if (!refresh && _directGeo != null) return _directGeo;
    final g = _fromMap(await KMultiProfiles.directGeo());
    if (g != null) _directGeo = g;
    return g ?? _directGeo;
  }

  /// Country of one proxy, asked THROUGH that proxy (it need not be applied).
  Future<ProxyGeo?> geoOfProxy(ProxyEntry p, {bool refresh = false}) async {
    if (!refresh && _geoCache.containsKey(p.id)) return _geoCache[p.id];
    final password = p.passwordEnc.isEmpty ? '' : await KMultiProfiles.decrypt(p.passwordEnc);
    final g = _fromMap(await KMultiProfiles.geoVia(
      scheme: p.scheme,
      host: p.host,
      port: p.port,
      username: p.username,
      password: password,
    ));
    if (g == null) return _geoCache[p.id];
    await _saveGeo(p.id, g);
    return g;
  }

  /// Looks up the country of every proxy in [list] that has none yet (3 at a time) and
  /// notifies listeners after each one, so flags appear as they arrive.
  Future<void> fillGeos(List<ProxyEntry> list) async {
    final todo = list.where((p) => !_geoCache.containsKey(p.id) && !_geoBusy.contains(p.id)).toList();
    if (todo.isEmpty) return;
    for (final p in todo) {
      _geoBusy.add(p.id);
    }
    notifyListeners();
    var next = 0;
    Future<void> worker() async {
      while (next < todo.length) {
        final p = todo[next++];
        try {
          await geoOfProxy(p);
        } catch (_) {}
        _geoBusy.remove(p.id);
        notifyListeners();
      }
    }

    await Future.wait([worker(), worker(), worker()]);
  }

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
    try {
      final g = await _db.query('app_settings', where: "key LIKE 'proxy_geo_%'");
      for (final r in g) {
        final id = int.tryParse('${r['key']}'.substring('proxy_geo_'.length));
        final geo = ProxyGeo.fromStorage(r['value'] as String?);
        if (id != null && geo != null && !_geoCache.containsKey(id)) _geoCache[id] = geo;
      }
    } catch (_) {}
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
    await _forgetGeo(id);
    await _db.update('proxies', values, where: 'id = ?', whereArgs: [id]);
    await load();
  }

  /// Deleting a proxy switches it off in every profile that used it.
  Future<void> delete(int id) async {
    await _db.delete('profile_settings', where: "key = 'proxy_id' AND value = ?", whereArgs: ['$id']);
    await _forgetGeo(id);
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
