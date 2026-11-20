import 'package:flutter/material.dart';

class AppColors {
  static const purple = Color(0xFF7351FF);
  static const gold = Color(0xFFF6C101);
  static const darkBase = Color(0xFF17151F);
  static const surface = Color(0xFF22202B);
  static const white = Color(0xFFFFFFFF);
}

class AppTheme {
  static ThemeData dark([Color accent = AppColors.purple]) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      secondary: AppColors.gold,
      surface: AppColors.darkBase,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkBase,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBase,
        foregroundColor: AppColors.white,
        elevation: 0,
      ),
    );
  }

  static ThemeData light([Color accent = AppColors.purple]) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: accent,
      secondary: AppColors.gold,
      // Pure white everywhere in light mode: pages, bars, dialogs, sheets and menus.
      surface: AppColors.white,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: AppColors.white,
      surfaceContainerLow: AppColors.white,
      surfaceContainer: AppColors.white,
      surfaceContainerHigh: AppColors.white,
      surfaceContainerHighest: const Color(0xFFF2F2F5),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.white,
      canvasColor: AppColors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}

/// Theme-aware colours that replace the old hard-coded white and dark values,
/// so every screen reads well in both light and dark mode.
extension AppThemeContext on BuildContext {
  bool get _isDark => Theme.of(this).brightness == Brightness.dark;

  /// Cards, text fields and panels.
  Color get panel => _isDark ? AppColors.surface : const Color(0xFFF2F2F5);

  /// Secondary text and icons.
  Color get muted => Theme.of(this).colorScheme.onSurface.withValues(alpha: 0.6);

  /// Subtle fills (avatars, unselected chips).
  Color get faint => Theme.of(this).colorScheme.onSurface.withValues(alpha: 0.12);
}
