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

String? _code(Uri uri) {
  final id = normaliseCode(uri.queryParameters['id']);
  return isValidCode(id) ? id : null;
}

LinkTarget _forPath(String path, Uri uri) {
  final p = path.replaceAll(RegExp(r'\.html$'), '').replaceAll(RegExp(r'^/+|/+$'), '');
  final focus = switch (uri.fragment) {
    'join' => 'join',
    'host' => 'host',
    _ => null,
  };
  switch (p) {
    case 'join':
      final tap = uri.queryParameters['tap'];
      return LinkJoin(_code(uri), tap != null && _token.hasMatch(tap) ? tap : null);
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
  if (text.startsWith('/') || text.startsWith('#')) return parseLink('$siteOrigin${text.startsWith('#') ? '/$text' : text}');
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
    final p = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (p == '/privacy' || p.startsWith('/api/')) return LinkOut(uri);
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
      return code == null ? '$siteOrigin/' : '$siteOrigin/host?id=$code';
    case AppPages.join:
      final code = AppPages.joinCode.value;
      return code == null ? '$siteOrigin/join' : '$siteOrigin/join?id=$code';
  }
  return '$siteOrigin/';
}

class Links {
  Links._();

  /// A link that came before the app was on screen, kept until it is.
  static String? pending;
  static bool shown = false;

  /// Opens a link. Returns false when it was nothing the app knows.
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
    final p = pending;
    pending = null;
    if (p != null) open(p);
  }
}
