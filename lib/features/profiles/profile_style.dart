import 'package:flutter/material.dart';

class ProfileStyle {
  static const Map<String, IconData> icons = {
    'person': Icons.person,
    'work': Icons.work,
    'video': Icons.smart_display,
    'science': Icons.science,
    'school': Icons.school,
    'shopping': Icons.shopping_bag,
    'code': Icons.code,
    'games': Icons.sports_esports,
    'favorite': Icons.favorite,
    'public': Icons.public,
    'home': Icons.home,
    'finance': Icons.account_balance,
  };

  static const List<String> colors = [
    '#7351FF', '#F6C101', '#E5484D', '#30A46C',
    '#0091FF', '#F76B15', '#E93D82', '#12A594',
  ];

  static IconData iconFor(String? key) => icons[key] ?? Icons.person;

  static Color colorFor(String? hex) {
    if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
      return const Color(0xFF7351FF);
    }
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  static String lastActiveShort(int? ms) {
    if (ms == null) return 'Not opened yet';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${h == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  static String lastActiveText(int? ms) {
    if (ms == null) return 'Not opened yet';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return 'Last active: just now';
    if (diff.inMinutes < 60) return 'Last active: ${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return 'Last active: $h ${h == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays == 1) return 'Last active: Yesterday';
    return 'Last active: ${diff.inDays} days ago';
  }
}
