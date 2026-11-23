// Picking pictures for a bug report: the system's file picker on every platform (Android's photo
// picker, which needs no permission).
import 'package:file_selector/file_selector.dart';

const imageTypes = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'heic'],
  mimeTypes: ['image/*'],
  uniformTypeIdentifiers: ['public.image'],
);

/// Opens the system's picker for pictures: several at once, or just one. An empty list when the
/// person picked nothing or the picker failed.
Future<List<XFile>> pickImages({bool multiple = true}) async {
  try {
    if (multiple) return await openFiles(acceptedTypeGroups: const [imageTypes]);
    final pickedFile = await openFile(acceptedTypeGroups: const [imageTypes]);
    if (pickedFile == null) {
      return const [];
    } else {
      return [pickedFile];
    }
  } catch (_) {
    return const [];
  }
}
