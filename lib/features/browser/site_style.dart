import 'package:flutter/material.dart';

const Map<String, int> _brands = {
  'google.com': 0xFF4285F4,
  'mail.google.com': 0xFFEA4335,
  'gmail.com': 0xFFEA4335,
  'youtube.com': 0xFFFF0000,
  'youtu.be': 0xFFFF0000,
  'wikipedia.org': 0xFF3366CC,
  'github.com': 0xFF6E5494,
  'duckduckgo.com': 0xFFDE5833,
  'bing.com': 0xFF008373,
  'reddit.com': 0xFFFF4500,
  'facebook.com': 0xFF1877F2,
  'instagram.com': 0xFFE4405F,
  'twitter.com': 0xFF1DA1F2,
  'x.com': 0xFF444B52,
  'whatsapp.com': 0xFF25D366,
  'linkedin.com': 0xFF0A66C2,
  'netflix.com': 0xFFE50914,
  'amazon.com': 0xFFFF9900,
  'tiktok.com': 0xFFFE2C55,
  'telegram.org': 0xFF26A5E4,
  't.me': 0xFF26A5E4,
  'spotify.com': 0xFF1DB954,
  'yahoo.com': 0xFF6001D2,
  'twitch.tv': 0xFF9146FF,
  'pinterest.com': 0xFFE60023,
  'stackoverflow.com': 0xFFF48024,
  'microsoft.com': 0xFF00A4EF,
  'outlook.com': 0xFF0078D4,
  'live.com': 0xFF0078D4,
  'paypal.com': 0xFF003087,
  'ebay.com': 0xFFE53238,
  'quora.com': 0xFFB92B27,
  'bbc.com': 0xFFBB1919,
  'bbc.co.uk': 0xFFBB1919,
  'cnn.com': 0xFFCC0000,
  'dropbox.com': 0xFF0061FF,
  'zoom.us': 0xFF2D8CFF,
  'discord.com': 0xFF5865F2,
};

const List<int> _fallback = [
  0xFF7351FF, 0xFFE5484D, 0xFF30A46C, 0xFF0091FF,
  0xFFF76B15, 0xFFE93D82, 0xFF12A594, 0xFFAB4ABA,
];

final List<String> _brandKeys = (_brands.keys.toList()..sort((a, b) => b.length.compareTo(a.length)));

/// Colour of a site circle: the site's brand colour when known (Google blue,
/// YouTube red, ...), otherwise a stable colour taken from the address.
Color siteColor(String url, String name) {
  var host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  if (host.isEmpty) host = name.toLowerCase();
  for (final k in _brandKeys) {
    if (host == k || host.endsWith('.$k')) return Color(_brands[k]!);
  }
  final i = host.codeUnits.fold<int>(0, (a, b) => a + b) % _fallback.length;
  return Color(_fallback[i]);
}
