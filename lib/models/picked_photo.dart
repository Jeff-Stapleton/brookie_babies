/// A file the admin picked to upload.
class PickedPhoto {
  const PickedPhoto({required this.name, required this.size, required this.contentType, required this.data});

  /// The file's name on the admin's computer: 'IMG_1.jpg'.
  final String name;

  /// In bytes.
  final int size;

  /// The browser's MIME type, or '' if it didn't say (it often doesn't for
  /// HEIC). PhotoRules.contentTypeFor fills the gap from the extension.
  final String contentType;

  /// The contents: the browser's `File` on the web (handed to Storage's
  /// putBlob untouched), or a `Uint8List` in tests.
  final Object data;
}
