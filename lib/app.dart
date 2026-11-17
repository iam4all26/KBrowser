import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/poc/poc_screen.dart';

class KMultiBrowserApp extends StatelessWidget {
  const KMultiBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K-Multi Browser',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const PocScreen(),
    );
  }
}
