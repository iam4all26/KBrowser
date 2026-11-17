class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.profileId,
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  final int id;
  final String profileId; // history belongs to exactly one profile
  final String url;
  final String title;
  final int visitedAt;

  factory HistoryEntry.fromMap(Map<String, Object?> m) => HistoryEntry(
        id: m['id'] as int,
        profileId: m['profile_id'] as String,
        url: m['url'] as String,
        title: (m['title'] as String?) ?? '',
        visitedAt: m['visited_at'] as int,
      );
}
