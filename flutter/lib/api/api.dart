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

  /// The data as a map, or an empty one when it isn't a map.
  Map<String, dynamic> get map {
    if (data is Map) {
      return Map<String, dynamic>.from(data as Map);
    }
    return const {};
  }

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
    String slashedPath;
    if (path.startsWith('/')) {
      slashedPath = path;
    } else {
      slashedPath = '/$path';
    }
    return Uri.parse('$base/api$slashedPath');
  }

  /// The site's own page addresses (privacy, the guide), from the same base.
  static Uri page(String path) {
    return Uri.parse('$base$path');
  }

  /// One request to /api, answered as an [ApiResult] whatever happens: the server's
  /// `{ ok, data, error, reason }` read into it, or the offline answer when it couldn't be reached.
  static Future<ApiResult> call(String path, {String method = 'GET', Object? body, Map<String, String> headers = const {}}) async {
    final request = http.Request(method, uri(path));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    request.headers.addAll(headers);
    late final http.Response response;
    try {
      response = await http.Response.fromStream(await client.send(request).timeout(const Duration(seconds: 30)));
    } catch (_) {
      offline.value = true;
      return ApiResult.offlineResult;
    }
    offline.value = false;
    Object? payload;
    try {
      payload = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      payload = null;
    }
    Map answer;
    if (payload is Map) {
      answer = payload;
    } else {
      answer = const {};
    }
    if (response.statusCode >= 200 && response.statusCode < 300 && answer['ok'] == true) {
      return ApiResult(ok: true, status: response.statusCode, data: answer['data']);
    }
    // The service worker's offline answer, on the site; here only a proxy would say it.
    if (answer['reason'] == 'offline') {
      offline.value = true;
      return ApiResult.offlineResult;
    }
    String error;
    if (answer['error'] is String && (answer['error'] as String).isNotEmpty) {
      error = answer['error'] as String;
    } else {
      error = 'Something went wrong. Try again.';
    }
    String reason;
    if (answer['reason'] is String) {
      reason = answer['reason'] as String;
    } else {
      reason = 'error';
    }
    return ApiResult(
      ok: false,
      status: response.statusCode,
      error: error,
      reason: reason,
      data: answer['data'],
    );
  }

  static Future<ApiResult> post(String path, Map<String, dynamic> body) {
    return call(path, method: 'POST', body: body);
  }

  /// A route that answers in its own shape (app-release, bug-report): the decoded JSON and the
  /// status, or null when the server was never reached.
  static Future<({int status, Map<String, dynamic> json})?> raw(String path, {String method = 'GET', Object? body}) async {
    final request = http.Request(method, uri(path));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await http.Response.fromStream(await client.send(request).timeout(const Duration(seconds: 30)));
      offline.value = false;
      Map<String, dynamic> json = {};
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) {
          json = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Not JSON: an empty answer.
      }
      return (status: response.statusCode, json: json);
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
  static void Function() onOnline(void Function() callback) {
    _onBack.add(callback);
    return () {
      _onBack.remove(callback);
    };
  }

  /// Watches [offline]: each time it goes offline, asks the site again every 15 seconds until it
  /// answers, and each time it comes back, calls everything given to [onOnline].
  static void watchOffline() {
    if (_watching) return;
    _watching = true;
    var wasOffline = offline.value;
    offline.addListener(() {
      final probe = _probe;
      if (probe != null) {
        probe.cancel();
      }
      if (wasOffline && !offline.value) {
        for (final callback in List.of(_onBack)) {
          try {
            callback();
          } catch (_) {
            // One listener's trouble isn't the others'.
          }
        }
      }
      wasOffline = offline.value;
      if (!offline.value) return;
      _probe = Timer.periodic(const Duration(seconds: 15), (timer) async {
        try {
          await client.head(Uri.parse('$base/manifest.json')).timeout(const Duration(seconds: 8));
          offline.value = false;
          timer.cancel();
        } catch (_) {
          // Still gone.
        }
      });
    });
  }
}
