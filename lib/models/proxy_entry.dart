/// A proxy server added once at the main Home. The password is stored encrypted.
class ProxyEntry {
  const ProxyEntry({
    required this.id,
    required this.name,
    required this.scheme,
    required this.host,
    required this.port,
    required this.username,
    required this.passwordEnc,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String scheme; // http | https | socks5
  final String host;
  final int port;
  final String username;
  final String passwordEnc; // Android Keystore encrypted, empty if none
  final int createdAt;

  String get address => '$scheme://$host:$port';
  bool get hasLogin => username.isNotEmpty;

  factory ProxyEntry.fromMap(Map<String, Object?> m) => ProxyEntry(
        id: m['id'] as int,
        name: (m['name'] as String?) ?? '',
        scheme: (m['scheme'] as String?) ?? 'http',
        host: (m['host'] as String?) ?? '',
        port: (m['port'] as int?) ?? 0,
        username: (m['username'] as String?) ?? '',
        passwordEnc: (m['password_enc'] as String?) ?? '',
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}
