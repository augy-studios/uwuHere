// Calls to the site's /api (main-site/js/api.js), in one shape whatever happens:
//
//   ApiResult(ok: true,  status, data)
//   ApiResult(ok: false, status, error, reason, data, offline)
//
// A network failure is not thrown. Offline is an ordinary answer in this app, and every caller
// has a sentence ready for it. Plus one notifier for whether the network is there at all, which
// the offline bar listens to.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The site's host: the API's base, the links the app opens, and the update check.
const siteHost = 'here.uwuapps.org';
const siteOrigin = 'https://$siteHost';

/// The Play build: no updater of its own (--dart-define=UWUHERE_PLAY=true).
const isPlayBuild = bool.fromEnvironment('UWUHERE_PLAY');

class ApiResult {
  const ApiResult({
    required this.ok,
    this.status = 0,
    this.data,
    this.error = '',
    this.reason = '',
    this.offline = false,
  });

  final bool ok;
  final int status;
  final dynamic data;

  /// A sentence for a person.
  final String error;

  /// A fixed slug the screens branch on ("not-host", "not-found", "ended"…).
  final String reason;
  final bool offline;

  Map<String, dynamic> get map => data is Map ? Map<String, dynamic>.from(data as Map) : const {};

  static const offlineResult = ApiResult(ok: false, error: 'You appear to be offline.', reason: 'offline', offline: true);
}

class Api {
  Api._();

  /// Where /api lives: the site, or for the Playwright suite's browser build the page's own
  /// origin (set by e2e/main_e2e.dart), where its routes answer.
  static String base = siteOrigin;

  /// For tests: answers instead of the network.
  static http.Client client = http.Client();

  /// True while the last request couldn't reach the server.
  static final ValueNotifier<bool> offline = ValueNotifier(false);

  static Uri uri(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base/api$p');
  }

  /// The site's own page addresses (privacy, the guide), from the same base.
  static Uri page(String path) => Uri.parse('$base$path');

  static Future<ApiResult> call(String path, {String method = 'GET', Object? body, Map<String, String> headers = const {}}) async {
    final req = http.Request(method, uri(path));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    req.headers.addAll(headers);
    late final http.Response res;
    try {
      res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 30)));
    } catch (_) {
      offline.value = true;
      return ApiResult.offlineResult;
    }
    offline.value = false;
    Object? payload;
    try {
      payload = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      payload = null;
    }
    final p = payload is Map ? payload : const {};
    if (res.statusCode >= 200 && res.statusCode < 300 && p['ok'] == true) {
      return ApiResult(ok: true, status: res.statusCode, data: p['data']);
    }
    // The service worker's offline answer, on the site; here only a proxy would say it.
    if (p['reason'] == 'offline') {
      offline.value = true;
      return ApiResult.offlineResult;
    }
    return ApiResult(
      ok: false,
      status: res.statusCode,
      error: p['error'] is String && (p['error'] as String).isNotEmpty ? p['error'] as String : 'Something went wrong. Try again.',
      reason: p['reason'] is String ? p['reason'] as String : 'error',
      data: p['data'],
    );
  }

  static Future<ApiResult> post(String path, Map<String, dynamic> body) => call(path, method: 'POST', body: body);

  /// A route that answers in its own shape (app-release, bug-report): the decoded JSON and the
  /// status, or null when the server was never reached.
  static Future<({int status, Map<String, dynamic> json})?> raw(String path, {String method = 'GET', Object? body}) async {
    final req = http.Request(method, uri(path));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    try {
      final res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 30)));
      offline.value = false;
      Map<String, dynamic> json = {};
      try {
        final v = jsonDecode(utf8.decode(res.bodyBytes));
        if (v is Map) json = Map<String, dynamic>.from(v);
      } catch (_) {
        // Not JSON: an empty answer.
      }
      return (status: res.statusCode, json: json);
    } catch (_) {
      offline.value = true;
      return null;
    }
  }

  /// Asks again, quietly, until the network is back. Started once, as the app opens.
  static Timer? _probe;
  static bool _watching = false;
  static final List<void Function()> _onBack = [];

  /// Called each time the network comes back (the site's `online` event). Answers the way to stop.
  static void Function() onOnline(void Function() fn) {
    _onBack.add(fn);
    return () => _onBack.remove(fn);
  }

  static void watchOffline() {
    if (_watching) return;
    _watching = true;
    var was = offline.value;
    offline.addListener(() {
      _probe?.cancel();
      if (was && !offline.value) {
        for (final fn in List.of(_onBack)) {
          try {
            fn();
          } catch (_) {
            // One listener's trouble isn't the others'.
          }
        }
      }
      was = offline.value;
      if (!offline.value) return;
      _probe = Timer.periodic(const Duration(seconds: 15), (t) async {
        try {
          await client.head(Uri.parse('$base/manifest.json')).timeout(const Duration(seconds: 8));
          offline.value = false;
          t.cancel();
        } catch (_) {
          // Still gone.
        }
      });
    });
  }
}
