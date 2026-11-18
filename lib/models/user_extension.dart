/// An extension (userscript) stored once in the main Home library.
class UserExtension {
  const UserExtension({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.matches,
    required this.excludes,
    required this.runAt,
    required this.code,
    required this.createdAt,
    this.sourceUrl,
  });

  final int id;
  final String name;
  final String version;
  final String description;
  final List<String> matches; // @match / @include patterns
  final List<String> excludes; // @exclude / @exclude-match patterns
  final String runAt; // document-start | document-end | document-idle
  final String code;
  final String? sourceUrl;
  final int createdAt;

  static List<String> _lines(Object? v) =>
      ((v as String?) ?? '').split('\n').where((e) => e.trim().isNotEmpty).toList();

  factory UserExtension.fromMap(Map<String, Object?> m) => UserExtension(
        id: m['id'] as int,
        name: (m['name'] as String?) ?? 'Extension',
        version: (m['version'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        matches: _lines(m['matches']),
        excludes: _lines(m['excludes']),
        runAt: (m['run_at'] as String?) ?? 'document-idle',
        code: (m['code'] as String?) ?? '',
        sourceUrl: m['source_url'] as String?,
        createdAt: m['created_at'] as int,
      );
}
