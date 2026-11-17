import 'package:kmulti_profiles/kmulti_profiles.dart';

/// A private browsing session is a temporary engine profile with no row in the
/// database. It is deleted (with all its cookies and site data) when the
/// private browser closes, and any leftover is removed at the next app start.
class PrivateSession {
  static const String prefix = 'kmprivate_';

  static Future<String> start() async {
    final name = '$prefix${DateTime.now().millisecondsSinceEpoch}';
    await KMultiProfiles.ensureProfile(name);
    return name;
  }

  /// Deletes the engine profile. The engine refuses while a WebView still uses
  /// it, so this retries for a while after the WebViews are destroyed.
  static Future<void> destroy(String name) async {
    const delays = [500, 1500, 4000, 10000];
    for (final ms in delays) {
      await Future<void>.delayed(Duration(milliseconds: ms));
      try {
        await KMultiProfiles.deleteProfile(name);
        return;
      } catch (_) {
        // still in use, try again
      }
    }
    // Anything left is removed by cleanupLeftovers() at the next start.
  }

  /// Run once at startup, before any private session exists.
  static Future<void> cleanupLeftovers() async {
    try {
      final all = await KMultiProfiles.listProfiles();
      for (final name in all) {
        if (!name.startsWith(prefix)) continue;
        try {
          await KMultiProfiles.deleteProfile(name);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
