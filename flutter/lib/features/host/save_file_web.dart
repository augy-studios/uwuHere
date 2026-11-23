import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A browser download, as the site makes one.
Future<String?> saveTextFilePlatform(String name, String text, String mimeType) async {
  final blob = web.Blob([utf8.encode(text).toJS].toJS, web.BlobPropertyBag(type: '$mimeType;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  final body = web.document.body;
  if (body != null) {
    body.append(link);
  }
  link.click();
  link.remove();
  Future<void>.delayed(const Duration(seconds: 1), () {
    web.URL.revokeObjectURL(url);
  });
  return 'Downloaded $name';
}
