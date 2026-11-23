import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// The desktop: into Downloads, as a browser would, with a number added rather than over a file
/// already there; where there's no Downloads folder, the system's save dialog.
Future<String?> saveTextFilePlatform(String name, String text, String mimeType) async {
  final bytes = utf8.encode(text);
  Directory? downloadsDirectory;
  try {
    downloadsDirectory = await getDownloadsDirectory();
  } catch (_) {
    downloadsDirectory = null;
  }
  if (downloadsDirectory == null) {
    final location = await getSaveLocation(suggestedName: name);
    if (location == null) return null;
    await File(location.path).writeAsBytes(bytes);
    return 'Saved';
  }
  await downloadsDirectory.create(recursive: true);
  // Split "list.csv" into "list" and ".csv" so a copy can be called "list (2).csv".
  final dotIndex = name.lastIndexOf('.');
  String nameWithoutExtension;
  String extension;
  if (dotIndex > 0) {
    nameWithoutExtension = name.substring(0, dotIndex);
    extension = name.substring(dotIndex);
  } else {
    nameWithoutExtension = name;
    extension = '';
  }
  var file = File('${downloadsDirectory.path}${Platform.pathSeparator}$name');
  for (var copyNumber = 2; file.existsSync() && copyNumber < 100; copyNumber = copyNumber + 1) {
    file = File('${downloadsDirectory.path}${Platform.pathSeparator}$nameWithoutExtension ($copyNumber)$extension');
  }
  await file.writeAsBytes(bytes);
  return 'Saved to Downloads as ${file.uri.pathSegments.last}';
}
