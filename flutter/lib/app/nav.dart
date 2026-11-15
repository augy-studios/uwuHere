// Getting about from anywhere: one navigator key and one messenger key, the toast every
// feature uses (the site's toast()), and the two small windows the site left to the browser
// (confirm() and prompt()).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/theme.dart';
import '../widgets/sheet.dart';

class AppNav {
  AppNav._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Round the whole app, for a picture of it (bug reports, the desktop's screenshot button).
  static final repaintKey = GlobalKey();

  static BuildContext? get context => navigatorKey.currentContext;

  /// The last few toasts, newest last: tests and the desktop's title bar read them.
  static final ValueNotifier<String> lastToast = ValueNotifier('');

  static void toast(String message, {bool error = false}) {
    lastToast.value = message;
    final m = messengerKey.currentState;
    final ctx = context;
    if (m == null || ctx == null) return;
    final c = UwuColors.of(ctx);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: error ? c.bg : null)),
        backgroundColor: error ? c.error : null,
        duration: const Duration(seconds: 3),
        width: MediaQuery.sizeOf(ctx).width > 560 ? 420 : null,
      ),
    );
  }

  /// The site's confirm(): true when agreed to.
  static Future<bool> confirm(String message, {String yes = 'Delete', bool danger = true}) async {
    final ctx = context;
    if (ctx == null) return false;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (context) {
        final c = UwuColors.of(context);
        return AlertDialog(
          content: Text(message, style: TextStyle(color: c.ink, fontSize: 15)),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: c.errorFill, foregroundColor: c.error) : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(yes),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  /// The site's prompt(): the words typed, or null when cancelled or left empty.
  static Future<String?> prompt(String label, {String initial = '', String ok = 'OK'}) async {
    final ctx = context;
    if (ctx == null) return null;
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: ctx,
      builder: (context) => AlertDialog(
        title: Text(label, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(ok)),
        ],
      ),
    );
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// Closes whatever windows are open over the app (signing out, a link arriving).
  static void closeSheets() {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    AppSheet.closeAll();
  }
}

/// Puts words on the clipboard.
Future<void> copyText(String text) => Clipboard.setData(ClipboardData(text: text));

/// Opens a link in the person's own browser (or mail app): never inside the app. True if it went.
Future<bool> openOutside(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
