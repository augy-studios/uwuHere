// The first launch after updating from the Capacitor app (1.0.x was the site in a WebView):
// everything the site kept in its localStorage for https://here.uwuapps.org (the events this phone
// hosts and their host keys, check-ins, the name last typed, the theme, the tray) brought into the
// app's own store as it was, once, and never over a value the app has set since. The old copy is
// left alone, so nothing's lost either way.
//
// A WebView that's never shown, given the site's address, reads its storage
// (MainActivity.java's App.migrate). There was no earlier desktop app, so nothing to read there.
import '../native/bridge.dart';
import 'store.dart';

class Migrate {
  Migrate._();

  static const doneKey = 'app.migrated';

  /// Brings the old app's values across, once.
  /// How many values came across this time (0 when it was done before, or there was nothing).
  static Future<int> run(Store store) async {
    if (store.has(doneKey)) return 0;
    Map<String, dynamic> items = const {};
    try {
      if (Native.available && Native.platform == 'android') {
        final answer = await Native.call('App', 'migrate');
        Map? migratedItems;
        if (answer != null) {
          migratedItems = answer['items'] as Map?;
        }
        if (migratedItems == null) {
          migratedItems = const {};
        }
        items = Map<String, dynamic>.from(migratedItems);
      }
    } catch (_) {
      // Nothing to read: a phone that never had the old app either.
    }
    var copiedCount = 0;
    items.forEach((key, value) {
      // Only the site's own, and never over anything the app has set since.
      if (value is! String || store.has(key)) {
        return;
      }
      if (!key.startsWith('uwuhere.') && !key.startsWith('tour.')) {
        return;
      }
      store.put(key, value);
      copiedCount = copiedCount + 1;
    });
    store.put(doneKey, DateTime.now().millisecondsSinceEpoch.toString());
    return copiedCount;
  }
}
