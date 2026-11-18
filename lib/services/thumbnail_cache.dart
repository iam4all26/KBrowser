import 'dart:typed_data';

/// Small page pictures for the tab switcher. Kept in memory for the current session only.
class ThumbnailCache {
  static final Map<String, Uint8List> _items = {};
  static const int _max = 80;

  static Uint8List? get(String tabId) => _items[tabId];

  static void put(String tabId, Uint8List bytes) {
    _items.remove(tabId);
    _items[tabId] = bytes;
    while (_items.length > _max) {
      _items.remove(_items.keys.first);
    }
  }

  static void remove(String tabId) => _items.remove(tabId);

  static void clear() => _items.clear();
}
