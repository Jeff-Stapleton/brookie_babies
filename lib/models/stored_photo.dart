/// A file in Firebase Storage: a session's photo, or one in the home page
/// photo library.
class StoredPhoto {
  const StoredPhoto({required this.name, required this.fullPath, this.url});

  /// Relative to its folder: 'IMG_1.jpg', or 'edits/IMG_1.jpg' in a
  /// subfolder.
  final String name;

  /// The whole path in the bucket: 'galleries/abc/IMG_1.jpg'.
  final String fullPath;

  /// A download link, for home page library photos only. Session photos are
  /// private, so they never get one.
  final Uri? url;
}
