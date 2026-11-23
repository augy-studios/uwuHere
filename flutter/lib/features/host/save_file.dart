// Saving the host's CSV: on Android into Downloads through the app's own code (Android 10 and
// later, no permission) or wherever the host picks (7 to 9); on the desktop into the Downloads
// folder; in a browser, a download. Answers what to say, or null when the host backed out.
import '../../app/env.dart';
import '../../native/bridge.dart';
import 'save_file_stub.dart' if (dart.library.io) 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart';

/// Saves [text] as a file called [name] of type [mimeType], through Android's own code when
/// it can and otherwise through this platform's way of saving. Answers the message to show,
/// or null when the host backed out of choosing where to save.
Future<String?> saveTextFile(String name, String text, String mimeType) async {
  if (Env.android && Native.has('savefile')) {
    try {
      final saved = await Native.call('Here', 'saveFile', {'name': name, 'text': text, 'mime': mimeType});
      if (saved != null && saved['where'] == 'downloads') {
        return 'Saved to Downloads as $name';
      }
      if (saved != null && saved['saved'] == true) {
        return 'Saved';
      }
      return null;
    } on NativeError catch (error) {
      if (error.message.isEmpty) {
        return 'Could not save the list.';
      } else {
        return error.message;
      }
    }
  }
  try {
    return await saveTextFilePlatform(name, text, mimeType);
  } catch (_) {
    return 'Could not save the list.';
  }
}
