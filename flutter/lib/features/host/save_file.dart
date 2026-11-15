// Saving the host's CSV: on Android into Downloads through the app's own code (Android 10 and
// later, no permission) or wherever the host picks (7 to 9); on the desktop into the Downloads
// folder; in a browser, a download. Answers what to say, or null when the host backed out.
import '../../app/env.dart';
import '../../native/bridge.dart';
import 'save_file_stub.dart' if (dart.library.io) 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart';

Future<String?> saveTextFile(String name, String text, String mime) async {
  if (Env.android && Native.has('savefile')) {
    try {
      final saved = await Native.call('Here', 'saveFile', {'name': name, 'text': text, 'mime': mime});
      if (saved?['where'] == 'downloads') return 'Saved to Downloads as $name';
      if (saved?['saved'] == true) return 'Saved';
      return null;
    } on NativeError catch (e) {
      return e.message.isEmpty ? 'Could not save the list.' : e.message;
    }
  }
  try {
    return await saveTextFilePlatform(name, text, mime);
  } catch (_) {
    return 'Could not save the list.';
  }
}
