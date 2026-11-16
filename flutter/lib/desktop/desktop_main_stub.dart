// Where there's no desktop (the browser build the Playwright suite drives): nothing to do.
Future<bool> runDesktopSubWindow(List<String> arguments) async {
  return false;
}

Future<void> desktopBeforeApp(List<String> arguments) async {}
Future<void> desktopAfterApp(List<String> arguments) async {}
