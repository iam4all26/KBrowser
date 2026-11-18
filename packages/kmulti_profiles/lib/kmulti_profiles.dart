import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Engine-level profile operations (AndroidX WebKit ProfileStore).
class KMultiProfiles {
  static const MethodChannel _channel = MethodChannel('kmulti/profiles');

  /// Keys: supported (bool), webViewVersion (String).
  static Future<Map<String, dynamic>> info() async {
    final r = await _channel.invokeMapMethod<String, dynamic>('info');
    return r ?? <String, dynamic>{};
  }

  static Future<void> ensureProfile(String name) =>
      _channel.invokeMethod<void>('ensureProfile', {'name': name});

  static Future<List<String>> listProfiles() async {
    final r = await _channel.invokeListMethod<String>('listProfiles');
    return r ?? <String>[];
  }

  /// Deletes the engine profile and all its data. Throws if the profile is in
  /// use by a live WebView. Returns true if a profile was deleted.
  static Future<bool> deleteProfile(String name) async {
    final r = await _channel.invokeMethod<bool>('deleteProfile', {'name': name});
    return r ?? false;
  }

  static Future<String?> cookies(String profile, String url) =>
      _channel.invokeMethod<String>('cookies', {'name': profile, 'url': url});

  /// Opens the Android share sheet with [text].
  static Future<void> share(String text) =>
      _channel.invokeMethod<void>('share', {'text': text});

  /// Opens the system Downloads app.
  static Future<void> openDownloads() => _channel.invokeMethod<void>('openDownloads');

  /// Makes ALL WebViews of the app use this proxy (scheme: http, https or socks5).
  /// Completes when WebView confirms the change. Throws if it cannot be applied.
  static Future<void> setProxy({
    required String scheme,
    required String host,
    required int port,
    String username = '',
    String password = '',
  }) =>
      _channel.invokeMethod<void>('setProxy', {
        'scheme': scheme,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
      });

  /// Removes the proxy: WebViews use the normal connection again.
  static Future<void> clearProxy() => _channel.invokeMethod<void>('setProxy', {'clear': true});

  /// Encrypts text with a key kept in the Android Keystore.
  static Future<String> encrypt(String text) async =>
      (await _channel.invokeMethod<String>('encrypt', {'text': text})) ?? '';

  static Future<String> decrypt(String text) async =>
      (await _channel.invokeMethod<String>('decrypt', {'text': text})) ?? '';
}

@immutable
class KPageState {
  const KPageState({
    this.url = '',
    this.title = '',
    this.canGoBack = false,
    this.canGoForward = false,
    this.finished = false,
    this.blocked = 0,
  });
  final String url;
  final String title;
  final bool canGoBack;
  final bool canGoForward;

  /// True for the event sent when a page finished loading.
  final bool finished;

  /// Number of ad and tracker requests blocked on the current page.
  final int blocked;
}

/// Find-in-page result. [active] is 1-based (0 when there is no match).
@immutable
class KFindState {
  const KFindState({this.active = 0, this.total = 0});
  final int active;
  final int total;
}

class KWebViewController {
  KWebViewController(int viewId)
      : _channel = MethodChannel('kmulti/webview_$viewId') {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPage':
          final a = Map<String, dynamic>.from(call.arguments as Map);
          state.value = KPageState(
            url: (a['url'] as String?) ?? '',
            title: (a['title'] as String?) ?? '',
            canGoBack: a['canGoBack'] == true,
            canGoForward: a['canGoForward'] == true,
            finished: a['finished'] == true,
            blocked: (a['blocked'] as num?)?.toInt() ?? 0,
          );
        case 'onProgress':
          progress.value = ((call.arguments as num) / 100).clamp(0.0, 1.0).toDouble();
        case 'onNewWindow':
          onNewWindow?.call(call.arguments as String);
        case 'onFind':
          final f = Map<String, dynamic>.from(call.arguments as Map);
          final total = (f['total'] as num?)?.toInt() ?? 0;
          final active = (f['active'] as num?)?.toInt() ?? 0;
          find.value = KFindState(active: total == 0 ? 0 : active + 1, total: total);
        case 'onDownload':
          final a = Map<String, dynamic>.from(call.arguments as Map);
          onDownloadMessage?.call((a['message'] as String?) ?? '');
      }
      return null;
    });
  }

  final MethodChannel _channel;
  final ValueNotifier<KPageState> state = ValueNotifier(const KPageState());

  /// Latest find-in-page result.
  final ValueNotifier<KFindState> find = ValueNotifier(const KFindState());

  /// Page load progress, 0.0 to 1.0 (1.0 means idle or finished).
  final ValueNotifier<double> progress = ValueNotifier(1.0);

  /// Called when a page asks to open a new window (target=_blank, window.open).
  void Function(String url)? onNewWindow;

  /// Called with a short message when a download starts or cannot start.
  void Function(String message)? onDownloadMessage;

  Future<void> loadUrl(String url) =>
      _channel.invokeMethod<void>('loadUrl', {'url': url});
  Future<void> loadTestPage() => _channel.invokeMethod<void>('loadTestPage');
  Future<void> reload() => _channel.invokeMethod<void>('reload');
  Future<void> stop() => _channel.invokeMethod<void>('stop');
  Future<void> goBack() => _channel.invokeMethod<void>('goBack');
  Future<void> goForward() => _channel.invokeMethod<void>('goForward');
  Future<void> findAll(String query) {
    if (query.isEmpty) find.value = const KFindState();
    return _channel.invokeMethod<void>('find', {'query': query});
  }

  Future<void> findNext(bool forward) =>
      _channel.invokeMethod<void>('findNext', {'forward': forward});

  Future<void> clearFind() {
    find.value = const KFindState();
    return _channel.invokeMethod<void>('clearFind');
  }

  /// Sets the extension scripts that run on every page of this WebView
  /// (replaces the previous set; applies to pages loaded afterwards).
  /// A small JPEG picture of the page as shown (null if it cannot be taken).
  Future<Uint8List?> captureThumbnail() => _channel.invokeMethod<Uint8List>('captureThumbnail');

  /// Turns the built-in ad and tracker request blocker on or off for this WebView.
  Future<void> setAdBlock(bool enabled) =>
      _channel.invokeMethod<void>('setAdBlock', {'enabled': enabled});

  Future<void> setExtensions(List<String> scripts) =>
      _channel.invokeMethod<void>('setExtensions', {'scripts': scripts});

  Future<void> setDesktopMode(bool enabled, {bool reload = true}) =>
      _channel.invokeMethod<void>('setDesktopMode', {'enabled': enabled, 'reload': reload});
}

/// A native WebView bound to one engine profile for its whole life.
class KProfileWebView extends StatelessWidget {
  const KProfileWebView({
    super.key,
    required this.profile,
    required this.onCreated,
  });

  final String profile;
  final void Function(KWebViewController controller) onCreated;

  static const String _viewType = 'kmulti/webview';

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        return PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: <String, dynamic>{'profile': profile},
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(
            (id) => onCreated(KWebViewController(id)),
          )
          ..create();
      },
    );
  }
}
