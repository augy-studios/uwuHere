// Where there's no desktop (the browser build the Playwright suite drives): nothing to do.
Future<bool> runDesktopSubWindow(List<String> args) async => false;
Future<void> desktopBeforeApp(List<String> args) async {}
Future<void> desktopAfterApp(List<String> args) async {}
