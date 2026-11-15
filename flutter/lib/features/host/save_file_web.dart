import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A browser download, as the site makes one.
Future<String?> saveTextFilePlatform(String name, String text, String mime) async {
  final blob = web.Blob([utf8.encode(text).toJS].toJS, web.BlobPropertyBag(type: '$mime;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(a);
  a.click();
  a.remove();
  Future<void>.delayed(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
  return 'Downloaded $name';
}
