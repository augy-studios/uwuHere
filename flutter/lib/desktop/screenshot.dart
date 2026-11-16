// The title bar's two screenshot buttons (docs/desktop-features-spec.md §5):
// - Screenshot: a picture of the app's content (not the title bar), copied to the clipboard and
//   saved in Downloads as "uwuHere YYYY-MM-DD HH.MM.SS.png".
// - Long screenshot: the whole page on show (home, an event's host page with all its list, a
//   check-in page), top to bottom, not just what's on screen, up to 16384 px tall; saved as
//   "… (long).png". Only one at a time.
// A notification says it's saved; clicking it shows it in its folder.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pasteboard/pasteboard.dart';

import '../app/nav.dart';
import '../app/pages.dart';
import '../theme/theme.dart';
import '../widgets/page_frame.dart';
import 'desk.dart';
import 'notify.dart';

class Screenshots {
  Screenshots._();

  static final ValueNotifier<bool> busy = ValueNotifier(false);
  static const maximumHeight = 16384.0;

  /// Now as "YYYY-MM-DD HH.MM.SS", for the file's name.
  static String _stamp() {
    final now = DateTime.now();
    String twoDigits(int value) {
      return value.toString().padLeft(2, '0');
    }

    return '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)} ${twoDigits(now.hour)}.${twoDigits(now.minute)}.${twoDigits(now.second)}';
  }

  /// A picture of what's under [key]'s repaint boundary, on the page's own solid background.
  static Future<ui.Image?> _capture(GlobalKey key, double pixelRatio) async {
    final boundaryContext = key.currentContext;
    RenderObject? box;
    if (boundaryContext != null) box = boundaryContext.findRenderObject();
    if (box is! RenderRepaintBoundary) return null;
    if (box.debugNeedsPaint) await Future<void>.delayed(const Duration(milliseconds: 40));
    final shot = await box.toImage(pixelRatio: pixelRatio);
    final context = key.currentContext;
    if (context == null || !context.mounted) return shot;
    return PageShots.solid(shot, UwuColors.of(context));
  }

  /// Saves [image] in Downloads as [name], copies it to the clipboard, and says so with a toast
  /// and a notification titled [notificationTitle] that shows the file in its folder.
  static Future<void> _save(ui.Image image, String name, String notificationTitle) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('no picture');
    final bytes = data.buffer.asUint8List();
    final downloadsFolder = Directory(Desktop.downloads)..createSync(recursive: true);
    final file = File('${downloadsFolder.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    try {
      await Pasteboard.writeImage(bytes);
    } catch (_) {}
    AppNav.toast('Screenshot copied and saved');
    DeskNotify.show(
      title: notificationTitle,
      body: name,
      onClick: () {
        Desktop.showInFolder(file.path);
      },
    );
  }

  static Future<void> take(BuildContext context) async {
    if (busy.value) return;
    busy.value = true;
    try {
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      final image = await _capture(AppNav.repaintKey, pixelRatio);
      if (image == null) throw StateError('nothing to capture');
      await _save(image, '${Desktop.name} ${_stamp()}.png', 'Screenshot saved');
    } catch (_) {
      AppNav.toast('Couldn’t take a screenshot', error: true);
    } finally {
      busy.value = false;
    }
  }

  /// The page on show drawn whole (lib/widgets/page_frame.dart's PageShots), then saved.
  static Future<void> takeLong(BuildContext context) async {
    if (busy.value) return;
    busy.value = true;
    try {
      final image = await PageShots.whole(AppPages.active(), ratio: MediaQuery.devicePixelRatioOf(context), maxHeight: maximumHeight);
      if (image == null) throw StateError('nothing drawn');
      await _save(image, '${Desktop.name} ${_stamp()} (long).png', 'Long screenshot saved');
    } catch (_) {
      AppNav.toast('Couldn’t take a screenshot', error: true);
    } finally {
      busy.value = false;
    }
  }
}
