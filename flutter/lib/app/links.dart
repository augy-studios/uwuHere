// Every link that opens the app goes through Links.open() (docs/flutter-android-app-spec.md §5):
// the site's own https links (verified with assetlinks.json, so a scanned QR code lands here),
// a tag from a host's phone (its link, with a one-time tap token), the uwu://here/ scheme shared
// with the sibling apps, notifications, launcher shortcuts and widgets, and on the desktop the
// command bar and the Jump List.
//
//   https://here.uwuapps.org/                       home
//   https://here.uwuapps.org/#join, /#host          home, at the code box or the new event's form
//   https://here.uwuapps.org/join?id=CODE           the check-in page (&tap=TOKEN from a tap)
//   https://here.uwuapps.org/host?id=CODE           the host page
//   uwu://here/…                                    the same paths
//   uwu://here/updates                              the Updates page (Android)
import '../api/api.dart';
import '../data/codes.dart';
import '../features/update/update_bar.dart';
import 'nav.dart';
import 'pages.dart';

const appScheme = 'uwu';
const appHost = 'here';

sealed class LinkTarget {
  const LinkTarget();
}

class LinkHome extends LinkTarget {
  const LinkHome([this.focus]);

  /// 'join' or 'host', or null for the top.
  final String? focus;
}

class LinkJoin extends LinkTarget {
  const LinkJoin(this.code, [this.tap]);

  /// A valid code, or null for the code box.
  final String? code;
  final String? tap;
}

class LinkHost extends LinkTarget {
  const LinkHost(this.code);
  final String? code;
}

class LinkUpdates extends LinkTarget {
  const LinkUpdates();
}

/// Somewhere else: opened in the browser.
class LinkOut extends LinkTarget {
  const LinkOut(this.uri);
  final Uri uri;
}

final _plainPath = RegExp(r'^[A-Za-z0-9/_\-.]*$');
final _token = RegExp(r'^[A-Za-z0-9._~-]{8,400}$');

/// The link's event code (its `id`), or null when it has none or it isn't a valid code.
String? _code(Uri uri) {
  final id = normaliseCode(uri.queryParameters['id']);
  if (isValidCode(id)) {
    return id;
  } else {
    return null;
  }
}

/// Which page a path is for (the site's own, or the app scheme's), with `.html` and the slashes
/// at either end left off.
LinkTarget _forPath(String path, Uri uri) {
  final cleanPath = path.replaceAll(RegExp(r'\.html$'), '').replaceAll(RegExp(r'^/+|/+$'), '');
  final focus = switch (uri.fragment) {
    'join' => 'join',
    'host' => 'host',
    _ => null,
  };
  switch (cleanPath) {
    case 'join':
      final tap = uri.queryParameters['tap'];
      // A tap token is only kept when it looks like one.
      String? validTap;
      if (tap != null && _token.hasMatch(tap)) {
        validTap = tap;
      }
      return LinkJoin(_code(uri), validTap);
    case 'host':
      return LinkHost(_code(uri));
    case 'updates':
      return const LinkUpdates();
  }
  return LinkHome(focus);
}

/// Reads a link, or null if it's nothing the app can open. Only plain path characters are taken
/// from the app's own scheme.
LinkTarget? parseLink(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  // A path typed into the desktop's command bar.
  if (text.startsWith('/') || text.startsWith('#')) {
    String path;
    if (text.startsWith('#')) {
      path = '/$text';
    } else {
      path = text;
    }
    return parseLink('$siteOrigin$path');
  }
  // Just a code, typed into the command bar: its check-in page.
  if (isValidCode(text) && text.replaceAll(RegExp('[^A-Za-z0-9]'), '').length == codeLength) return LinkJoin(normaliseCode(text));
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) return null;
  if (uri.scheme == appScheme) {
    if (uri.host.toLowerCase() != appHost) return null;
    if (!_plainPath.hasMatch(uri.path)) return null;
    return _forPath(uri.path, uri);
  }
  if ((uri.scheme == 'https' || uri.scheme == 'http') && uri.host == siteHost) {
    // The site's pages the app doesn't draw (privacy, the guide) open in the browser.
    final pathWithoutTrailingSlash = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (pathWithoutTrailingSlash == '/privacy' || pathWithoutTrailingSlash.startsWith('/api/')) return LinkOut(uri);
    return _forPath(uri.path, uri);
  }
  if (uri.scheme == 'https' || uri.scheme == 'http' || uri.scheme == 'mailto') return LinkOut(uri);
  return null;
}

/// The site's address for what's on show, as the desktop's Copy link gives it.
String linkForPage() {
  switch (AppPages.active()) {
    case AppPages.host:
      final code = AppPages.hostCode.value;
      if (code == null) {
        return '$siteOrigin/';
      } else {
        return '$siteOrigin/host?id=$code';
      }
    case AppPages.join:
      final code = AppPages.joinCode.value;
      if (code == null) {
        return '$siteOrigin/join';
      } else {
        return '$siteOrigin/join?id=$code';
      }
  }
  return '$siteOrigin/';
}

class Links {
  Links._();

  /// A link that came before the app was on screen, kept until it is.
  static String? pending;
  static bool shown = false;

  /// Opens a link. Returns false when it was nothing the app knows. Before the app is on screen,
  /// a link to one of its own pages is kept in [pending] and opened by [appShown].
  static Future<bool> open(String raw) async {
    final target = parseLink(raw);
    if (target == null) return false;
    if (!shown && target is! LinkOut) {
      pending = raw;
      return true;
    }
    switch (target) {
      case LinkHome(:final focus):
        AppNav.closeSheets();
        AppPages.open(AppPages.home);
        if (focus != null) AppPages.homeFocus.value = focus;
      case LinkOut(:final uri):
        await openOutside(uri);
      case LinkJoin(:final code, :final tap):
        AppNav.closeSheets();
        AppPages.openJoin(code, tap: tap);
      case LinkHost(:final code):
        AppNav.closeSheets();
        if (code == null) {
          AppPages.open(AppPages.home);
        } else {
          AppPages.openHost(code);
        }
      case LinkUpdates():
        await openUpdates();
    }
    return true;
  }

  /// Once the app is on screen: a link that opened it, now usable.
  static void appShown() {
    shown = true;
    final pendingLink = pending;
    pending = null;
    if (pendingLink != null) open(pendingLink);
  }
}
