// Picking pictures for a bug report: the system's file picker on every platform (Android's photo
// picker, which needs no permission).
import 'package:file_selector/file_selector.dart';

const imageTypes = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'heic'],
  mimeTypes: ['image/*'],
  uniformTypeIdentifiers: ['public.image'],
);

Future<List<XFile>> pickImages({bool multiple = true}) async {
  try {
    if (multiple) return await openFiles(acceptedTypeGroups: const [imageTypes]);
    final f = await openFile(acceptedTypeGroups: const [imageTypes]);
    return f == null ? const [] : [f];
  } catch (_) {
    return const [];
  }
}
