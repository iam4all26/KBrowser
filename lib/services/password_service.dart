import 'package:kmulti_profiles/kmulti_profiles.dart';
import 'package:sqflite/sqflite.dart';

/// Result of comparing a submitted login with what is saved.
enum PwCheck { invalid, added, changed, same }

class SavedLogin {
  const SavedLogin({required this.id, required this.origin, required this.username, required this.updatedAt});
  final int id;
  final String origin; // scheme://host[:port]
  final String username;
  final int updatedAt;

  String get host => Uri.tryParse(origin)?.host ?? origin;
}

/// Saved logins of ONE profile (table `passwords`). Passwords are encrypted with the
/// Android Keystore key; usernames and sites are stored as plain text.
class PasswordService {
  PasswordService(this._db, this.profileId);

  final Database _db;
  final String profileId;

  /// scheme://host[:port] of an http(s) address, or null for anything else.
  static String? originOf(String url) {
    final u = Uri.tryParse(url);
    if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) return null;
    final def = u.scheme == 'https' ? 443 : 80;
    return '${u.scheme}://${u.host.toLowerCase()}${u.port != def ? ':${u.port}' : ''}';
  }

  SavedLogin _row(Map<String, Object?> m) => SavedLogin(
        id: m['id'] as int,
        origin: m['origin'] as String,
        username: (m['username'] as String?) ?? '',
        updatedAt: m['updated_at'] as int,
      );

  Future<List<SavedLogin>> forOrigin(String origin) async {
    final r = await _db.query(
      'passwords',
      where: 'profile_id = ? AND origin = ?',
      whereArgs: [profileId, origin],
      orderBy: 'updated_at DESC',
    );
    return r.map(_row).toList();
  }

  Future<List<SavedLogin>> all({String query = ''}) async {
    final q = query.trim().toLowerCase();
    final r = await _db.query(
      'passwords',
      where: q.isEmpty ? 'profile_id = ?' : 'profile_id = ? AND (origin LIKE ? OR username LIKE ?)',
      whereArgs: q.isEmpty ? [profileId] : [profileId, '%$q%', '%$q%'],
      orderBy: 'origin ASC, username ASC',
    );
    return r.map(_row).toList();
  }

  /// Does not write anything: tells whether the login is new, changed or already saved.
  Future<PwCheck> check(String url, String username, String password) async {
    final origin = originOf(url);
    if (origin == null || password.isEmpty) return PwCheck.invalid;
    final r = await _db.query(
      'passwords',
      where: 'profile_id = ? AND origin = ? AND username = ?',
      whereArgs: [profileId, origin, username],
      limit: 1,
    );
    if (r.isEmpty) return PwCheck.added;
    try {
      final old = await KMultiProfiles.decrypt(r.first['password_enc'] as String);
      return old == password ? PwCheck.same : PwCheck.changed;
    } catch (_) {
      return PwCheck.changed;
    }
  }

  Future<void> store(String url, String username, String password) async {
    final origin = originOf(url);
    if (origin == null || password.isEmpty) return;
    final enc = await KMultiProfiles.encrypt(password);
    final now = DateTime.now().millisecondsSinceEpoch;
    final r = await _db.query(
      'passwords',
      columns: ['id'],
      where: 'profile_id = ? AND origin = ? AND username = ?',
      whereArgs: [profileId, origin, username],
      limit: 1,
    );
    if (r.isEmpty) {
      await _db.insert('passwords', {
        'profile_id': profileId,
        'origin': origin,
        'username': username,
        'password_enc': enc,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await _db.update(
        'passwords',
        {'password_enc': enc, 'updated_at': now},
        where: 'id = ? AND profile_id = ?',
        whereArgs: [r.first['id'], profileId],
      );
    }
  }

  Future<String> reveal(int id) async {
    final r = await _db.query(
      'passwords',
      columns: ['password_enc'],
      where: 'id = ? AND profile_id = ?',
      whereArgs: [id, profileId],
      limit: 1,
    );
    if (r.isEmpty) return '';
    return KMultiProfiles.decrypt(r.first['password_enc'] as String);
  }

  Future<void> delete(int id) =>
      _db.delete('passwords', where: 'id = ? AND profile_id = ?', whereArgs: [id, profileId]);

  Future<void> deleteAll() => _db.delete('passwords', where: 'profile_id = ?', whereArgs: [profileId]);
}
