class SearchEngine {
  const SearchEngine(this.id, this.name, this.searchUrl, this.homeUrl);
  final String id;
  final String name;
  final String searchUrl; // %s is replaced by the encoded query
  final String homeUrl;
}

class SearchEngines {
  static const google = SearchEngine(
    'google', 'Google', 'https://www.google.com/search?q=%s', 'https://www.google.com',
  );
  static const bing = SearchEngine(
    'bing', 'Bing', 'https://www.bing.com/search?q=%s', 'https://www.bing.com',
  );
  static const duckduckgo = SearchEngine(
    'duckduckgo', 'DuckDuckGo', 'https://duckduckgo.com/?q=%s', 'https://duckduckgo.com',
  );

  static const List<SearchEngine> all = [google, bing, duckduckgo];

  static SearchEngine byId(String? id) {
    for (final e in all) {
      if (e.id == id) return e;
    }
    return google;
  }
}

final RegExp _hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');
final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/.*)?$');

/// Turns what the user typed into a URL: addresses get https:// by default,
/// anything else becomes a search.
String resolveInput(String raw, SearchEngine engine) {
  final t = raw.trim();
  if (t.isEmpty) return engine.homeUrl;
  final lower = t.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return t;
  if (_hasScheme.hasMatch(t)) {
    // Other schemes (ftp, file, ...) are not opened from the address bar.
    return engine.searchUrl.replaceFirst('%s', Uri.encodeQueryComponent(t));
  }
  final hasSpace = t.contains(' ');
  final looksLikeHost = !hasSpace &&
      (lower.startsWith('localhost') ||
          _ipv4.hasMatch(t) ||
          (t.contains('.') && !t.startsWith('.') && !t.endsWith('.')));
  if (looksLikeHost) return 'https://$t';
  return engine.searchUrl.replaceFirst('%s', Uri.encodeQueryComponent(t));
}
