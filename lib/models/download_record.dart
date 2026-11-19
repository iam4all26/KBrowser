/// A file saved from a profile's browser (kept per profile).
class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.profileId,
    required this.name,
    required this.location,
    required this.isUri,
    required this.mime,
    required this.size,
    required this.sourceUrl,
    required this.createdAt,
  });

  final int id;
  final String profileId;
  final String name;
  final String location; // content:// address (Android 10+) or a file path
  final bool isUri;
  final String mime;
  final int size;
  final String sourceUrl;
  final int createdAt;

  /// True when the file is in the app's own folder (not the public Downloads folder).
  bool get inAppFolder => !isUri && location.contains('/Android/data/');

  factory DownloadRecord.fromMap(Map<String, Object?> m) => DownloadRecord(
        id: m['id'] as int,
        profileId: m['profile_id'] as String,
        name: (m['name'] as String?) ?? '',
        location: (m['location'] as String?) ?? '',
        isUri: (m['is_uri'] as int? ?? 0) == 1,
        mime: (m['mime'] as String?) ?? '',
        size: (m['size'] as int?) ?? 0,
        sourceUrl: (m['source_url'] as String?) ?? '',
        createdAt: m['created_at'] as int,
      );
}
