class AppProfile {
  const AppProfile({
    required this.id,
    required this.engineProfileName,
    required this.displayName,
    this.icon,
    this.color,
    this.isDefault = false,
    this.isLocked = false,
    this.isActive = false,
    this.desktopMode = false,
    required this.createdAt,
    required this.updatedAt,
    this.lastActiveAt,
  });

  final String id;
  final String engineProfileName; // immutable, names the Chromium storage
  final String displayName; // editable
  final String? icon;
  final String? color;
  final bool isDefault;
  final bool isLocked;
  final bool isActive;
  final bool desktopMode;
  final int createdAt;
  final int updatedAt;
  final int? lastActiveAt;

  /// Number from the permanent id (km_007 -> 7).
  int get number => int.tryParse(id.replaceFirst('km_', '')) ?? 0;

  factory AppProfile.fromMap(Map<String, Object?> m) {
    return AppProfile(
      id: m['id'] as String,
      engineProfileName: m['engine_profile_name'] as String,
      displayName: m['display_name'] as String,
      icon: m['icon'] as String?,
      color: m['color'] as String?,
      isDefault: (m['is_default'] as int? ?? 0) == 1,
      isLocked: (m['is_locked'] as int? ?? 0) == 1,
      isActive: (m['is_active'] as int? ?? 0) == 1,
      desktopMode: (m['desktop_mode'] as int? ?? 0) == 1,
      createdAt: m['created_at'] as int,
      updatedAt: m['updated_at'] as int,
      lastActiveAt: m['last_active_at'] as int?,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'engine_profile_name': engineProfileName,
        'display_name': displayName,
        'icon': icon,
        'color': color,
        'is_default': isDefault ? 1 : 0,
        'is_locked': isLocked ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'desktop_mode': desktopMode ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'last_active_at': lastActiveAt,
      };

  AppProfile copyWith({
    String? displayName,
    String? icon,
    String? color,
    bool? isLocked,
    bool? isActive,
    bool? desktopMode,
    int? updatedAt,
    int? lastActiveAt,
  }) {
    return AppProfile(
      id: id,
      engineProfileName: engineProfileName,
      displayName: displayName ?? this.displayName,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isDefault: isDefault,
      isLocked: isLocked ?? this.isLocked,
      isActive: isActive ?? this.isActive,
      desktopMode: desktopMode ?? this.desktopMode,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }
}
