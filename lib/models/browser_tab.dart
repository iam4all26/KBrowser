class BrowserTab {
  const BrowserTab({
    required this.id,
    required this.profileId,
    required this.url,
    required this.title,
    required this.position,
    required this.isActive,
    required this.desktopMode,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String profileId; // a tab belongs to exactly one profile
  final String url;
  final String title;
  final int position;
  final bool isActive;
  final bool desktopMode;
  final int createdAt;
  final int updatedAt;

  factory BrowserTab.fromMap(Map<String, Object?> m) => BrowserTab(
        id: m['id'] as String,
        profileId: m['profile_id'] as String,
        url: (m['url'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        position: (m['position'] as int?) ?? 0,
        isActive: (m['is_active'] as int? ?? 0) == 1,
        desktopMode: (m['desktop_mode'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'profile_id': profileId,
        'url': url,
        'title': title,
        'position': position,
        'is_active': isActive ? 1 : 0,
        'desktop_mode': desktopMode ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  BrowserTab copyWith({
    String? url,
    String? title,
    int? position,
    bool? isActive,
    bool? desktopMode,
    int? updatedAt,
  }) =>
      BrowserTab(
        id: id,
        profileId: profileId,
        url: url ?? this.url,
        title: title ?? this.title,
        position: position ?? this.position,
        isActive: isActive ?? this.isActive,
        desktopMode: desktopMode ?? this.desktopMode,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
