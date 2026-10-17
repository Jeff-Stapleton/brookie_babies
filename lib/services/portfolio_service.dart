import 'dart:developer';

import 'package:firebase_storage/firebase_storage.dart';

/// The photographs shown on the home page. [StoragePortfolioService] is the
/// real implementation; tests use a fake.
abstract class PortfolioService {
  /// Download links for the portfolio photos, sorted by file name: at most
  /// [limit] of them, the first ones by name. The first one is the home
  /// page's hero, so the photographer chooses it by naming.
  ///
  /// A photo whose link can't be fetched is left out rather than failing
  /// the rest.
  Future<List<Uri>> photoUrls({int? limit});
}

/// Lists Firebase Storage's public `_admin/gallery` folder (storage.rules lets
/// anyone read it).
class StoragePortfolioService implements PortfolioService {
  StoragePortfolioService(this._storage);

  final FirebaseStorage _storage;

  static const folder = '_admin/gallery';

  /// Whether a file in [folder] is a photo browsers can show: a JPEG, PNG or
  /// WebP, by extension in any case. Hidden files (".DS_Store") and anything
  /// else, such as an iPhone's HEIC, are skipped.
  static bool isPhoto(String name) => !name.startsWith('.') && _photoExtension.hasMatch(name);

  static final _photoExtension = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);

  @override
  Future<List<Uri>> photoUrls({int? limit}) async {
    final listing = await _storage.ref(folder).listAll();
    final files = [
      for (final file in listing.items)
        if (isPhoto(file.name)) file,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final urls = await Future.wait((limit == null ? files : files.take(limit)).map(_downloadUrl));
    return [
      for (final url in urls)
        if (url != null) url,
    ];
  }

  Future<Uri?> _downloadUrl(Reference file) async {
    try {
      return Uri.parse(await file.getDownloadURL());
    } catch (e) {
      log('Could not get a link for portfolio photo ${file.name}: $e');
      return null;
    }
  }
}
