import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// The desktop: into Downloads, as a browser would, with a number added rather than over a file
/// already there; where there's no Downloads folder, the system's save dialog.
Future<String?> saveTextFilePlatform(String name, String text, String mime) async {
  final bytes = utf8.encode(text);
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    dir = null;
  }
  if (dir == null) {
    final where = await getSaveLocation(suggestedName: name);
    if (where == null) return null;
    await File(where.path).writeAsBytes(bytes);
    return 'Saved';
  }
  await dir.create(recursive: true);
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var file = File('${dir.path}${Platform.pathSeparator}$name');
  for (var n = 2; file.existsSync() && n < 100; n++) {
    file = File('${dir.path}${Platform.pathSeparator}$stem ($n)$ext');
  }
  await file.writeAsBytes(bytes);
  return 'Saved to Downloads as ${file.uri.pathSegments.last}';
}
