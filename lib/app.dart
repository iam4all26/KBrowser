import 'package:flutter/material.dart';

import 'core/database/app_database.dart';
import 'core/theme/app_theme.dart';
import 'features/profiles/profile_dashboard_screen.dart';
import 'services/profile_service.dart';

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
      home: const _Boot(),
    );
  }
}

/// Opens the database, reconciles engine profiles, then shows the dashboard.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  ProfileService? _service;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final db = await AppDatabase.open();
      final service = ProfileService(db);
      await service.init();
      if (!mounted) return;
      setState(() => _service = service);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service != null) return ProfileDashboardScreen(service: service);
    return Scaffold(
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not start: $_error', textAlign: TextAlign.center),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset('assets/icon/app_icon.png', width: 88, height: 88),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'K-Multi Browser',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ],
              ),
      ),
    );
  }
}
