import 'dart:developer';

import 'package:firebase_storage/firebase_storage.dart';

/// The photographs shown on the home page. [StoragePortfolioService] is the
/// real implementation; tests use a fake.
abstract class PortfolioService {
  /// Download links for the portfolio photos, in the order they are shown:
  /// at most [limit] of them. The first one is the home page's hero.
  ///
  /// A photo whose link can't be fetched is left out rather than failing
  /// the rest.
  Future<List<Uri>> photoUrls({int? limit});
}

/// Photos from Firebase Storage's public `_admin/gallery` folder
/// (storage.rules lets anyone read it): the ones an admin chose for the home
/// page, in their order, or until one has, every photo there by file name.
class StoragePortfolioService implements PortfolioService {
  StoragePortfolioService(
    this._storage, {
    required Future<List<String>?> Function() homePhotoNames,
    this.homePhotoNamesTimeLimit = const Duration(seconds: 3),
  }) : _homePhotoNames = homePhotoNames;

  final FirebaseStorage _storage;

  /// The chosen photos' file names (AdminService.homePhotoNames): null if
  /// none were ever chosen.
  final Future<List<String>?> Function() _homePhotoNames;

  /// How long the home page waits for the chosen names before it lists the
  /// folder instead, so a slow or failing read never holds up the hero.
  final Duration homePhotoNamesTimeLimit;

  static const folder = '_admin/gallery';

  /// Whether a file in [folder] is a photo browsers can show: a JPEG, PNG or
  /// WebP, by extension in any case. Hidden files (".DS_Store") and anything
  /// else, such as an iPhone's HEIC, are skipped.
  static bool isPhoto(String name) => !name.startsWith('.') && _photoExtension.hasMatch(name);

  static final _photoExtension = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);

  @override
  Future<List<Uri>> photoUrls({int? limit}) async {
    final chosen = await _chosenNames();
    final List<Reference> files;
    if (chosen != null) {
      final folderRef = _storage.ref(folder);
      final seen = <String>{};
      files = [
        // Only names directly in the folder: `photos` is a plain list, so
        // the rules can't check what's in it.
        for (final name in chosen)
          if (!name.contains('/') && isPhoto(name) && seen.add(name)) folderRef.child(name),
      ];
    } else {
      final listing = await _storage.ref(folder).listAll();
      files = [
        for (final file in listing.items)
          if (isPhoto(file.name)) file,
      ]..sort((a, b) => a.name.compareTo(b.name));
    }
    final urls = await Future.wait((limit == null ? files : files.take(limit)).map(_downloadUrl));
    return [
      for (final url in urls)
        if (url != null) url,
    ];
  }

  /// The chosen names, or null to fall back to the folder's (none chosen,
  /// or they couldn't be read in time).
  Future<List<String>?> _chosenNames() async {
    try {
      return await _homePhotoNames().timeout(homePhotoNamesTimeLimit);
    } catch (e) {
      log('Could not read the chosen home page photos, so showing the gallery by name: $e');
      return null;
    }
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
