import 'dart:typed_data';

/// A site shown in the "Popular" tab of the main Home. App-wide, not per profile.
class HomeShortcut {
  const HomeShortcut({
    required this.id,
    required this.url,
    required this.title,
    required this.pinned,
    required this.createdAt,
    this.image,
  });

  final int id;
  final String url;
  final String title;
  final bool pinned;
  final int createdAt;
  final Uint8List? image; // optional picture chosen by the user

  factory HomeShortcut.fromMap(Map<String, Object?> m) => HomeShortcut(
        id: m['id'] as int,
        url: m['url'] as String,
        title: (m['title'] as String?) ?? '',
        pinned: (m['pinned'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as int,
        image: m['image'] as Uint8List?,
      );
}
