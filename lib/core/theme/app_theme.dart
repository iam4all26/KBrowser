import 'package:flutter/material.dart';

class AppColors {
  static const purple = Color(0xFF7351FF);
  static const gold = Color(0xFFF6C101);
  static const darkBase = Color(0xFF17151F);
  static const surface = Color(0xFF22202B);
  static const white = Color(0xFFFFFFFF);
}

class AppTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.purple,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.purple,
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

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.purple,
      brightness: Brightness.light,
    ).copyWith(primary: AppColors.purple, secondary: AppColors.gold);
    return ThemeData(useMaterial3: true, colorScheme: scheme);
  }
}
