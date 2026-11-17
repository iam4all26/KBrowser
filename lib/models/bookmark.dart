class Bookmark {
  const Bookmark({
    required this.id,
    required this.profileId,
    required this.url,
    required this.title,
    required this.createdAt,
  });

  final int id;
  final String profileId; // bookmarks belong to exactly one profile
  final String url;
  final String title;
  final int createdAt;

  factory Bookmark.fromMap(Map<String, Object?> m) => Bookmark(
        id: m['id'] as int,
        profileId: m['profile_id'] as String,
        url: m['url'] as String,
        title: (m['title'] as String?) ?? '',
        createdAt: m['created_at'] as int,
      );
}
