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

  static BuildContext? get context {
    return navigatorKey.currentContext;
  }

  /// The last few toasts, newest last: tests and the desktop's title bar read them.
  static final ValueNotifier<String> lastToast = ValueNotifier('');

  /// Shows a short message at the bottom of the app (in the error colour for [error]), replacing
  /// any message already showing.
  static void toast(String message, {bool error = false}) {
    lastToast.value = message;
    final messenger = messengerKey.currentState;
    final currentContext = context;
    if (messenger == null || currentContext == null) return;
    final colors = UwuColors.of(currentContext);
    messenger.hideCurrentSnackBar();
    // An error is drawn in the error colour; anything else in the theme's own snack bar colours.
    Color? textColor;
    Color? backgroundColor;
    if (error) {
      textColor = colors.bg;
      backgroundColor = colors.error;
    }
    // On a wide window the message keeps to a fixed width rather than spanning the whole bottom.
    double? snackBarWidth;
    if (MediaQuery.sizeOf(currentContext).width > 560) {
      snackBarWidth = 420;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: textColor)),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
        width: snackBarWidth,
      ),
    );
  }

  /// The site's confirm(): true when agreed to.
  static Future<bool> confirm(String message, {String yes = 'Delete', bool danger = true}) async {
    final currentContext = context;
    if (currentContext == null) return false;
    final agreed = await showDialog<bool>(
      context: currentContext,
      builder: (context) {
        final colors = UwuColors.of(context);
        // A dangerous action's button is drawn in the error colours.
        ButtonStyle? agreeButtonStyle;
        if (danger) {
          agreeButtonStyle = FilledButton.styleFrom(backgroundColor: colors.errorFill, foregroundColor: colors.error);
        }
        return AlertDialog(
          content: Text(message, style: TextStyle(color: colors.ink, fontSize: 15)),
          actions: [
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: agreeButtonStyle,
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(yes),
            ),
          ],
        );
      },
    );
    return agreed == true;
  }

  /// The site's prompt(): the words typed, or null when cancelled or left empty.
  static Future<String?> prompt(String label, {String initial = '', String ok = 'OK'}) async {
    final currentContext = context;
    if (currentContext == null) return null;
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: currentContext,
      builder: (context) {
        return AlertDialog(
          title: Text(label, style: const TextStyle(fontSize: 16)),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (typedText) {
              Navigator.pop(context, typedText);
            },
          ),
          actions: [
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, controller.text);
              },
              child: Text(ok),
            ),
          ],
        );
      },
    );
    if (value == null) return null;
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) return null;
    return trimmedValue;
  }

  /// Closes whatever windows are open over the app (signing out, a link arriving).
  static void closeSheets() {
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.popUntil((route) {
        return route.isFirst;
      });
    }
    AppSheet.closeAll();
  }
}

/// Puts words on the clipboard.
Future<void> copyText(String text) {
  return Clipboard.setData(ClipboardData(text: text));
}

/// Opens a link in the person's own browser (or mail app): never inside the app. True if it went.
Future<bool> openOutside(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
