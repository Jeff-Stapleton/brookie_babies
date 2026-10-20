import 'dart:async';
import 'dart:developer';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

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
    this.onLateChoice,
  }) : _homePhotoNames = homePhotoNames;

  final FirebaseStorage _storage;

  /// The chosen photos' file names (AdminService.homePhotoNames): null if
  /// none were ever chosen.
  final Future<List<String>?> Function() _homePhotoNames;

  /// How long the home page waits for the chosen names before it shows the
  /// last ones read, or the folder by name, so a slow or failing read never
  /// holds up the hero.
  final Duration homePhotoNamesTimeLimit;

  /// Called when the chosen names answer after [homePhotoNamesTimeLimit]
  /// and aren't the photos [photoUrls] fell back on, so they can be asked
  /// for again (HomePage.reloadPhotos): they are kept for that.
  final void Function()? onLateChoice;

  /// The last answer the chosen names' read gave, in time or late: what a
  /// read that can't answer in time falls back on. Null (none chosen, or no
  /// answer yet) is the folder by name.
  List<String>? _lastChosen;

  /// Counts the reads, so only the newest one's late answer counts.
  int _reads = 0;

  static const folder = '_admin/gallery';

  /// Whether a file in [folder] is a photo browsers can show: a JPEG, PNG or
  /// WebP, by extension in any case. Hidden files (".DS_Store") and anything
  /// else, such as an iPhone's HEIC, are skipped.
  static bool isPhoto(String name) => !name.startsWith('.') && _photoExtension.hasMatch(name);

  static final _photoExtension = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);

  @override
  Future<List<Uri>> photoUrls({int? limit}) async {
    final names = Future.sync(_homePhotoNames);
    // Listed meanwhile, so falling back costs no more than the wait.
    final listing = Future.sync(() => _storage.ref(folder).listAll())..ignore();
    final chosen = await _chosenNames(names, listing, limit);
    final List<Reference> files;
    if (chosen != null) {
      final folderRef = _storage.ref(folder);
      files = [for (final name in _shown(chosen, limit)) folderRef.child(name)];
    } else {
      files = _byName(await listing, limit);
    }
    final urls = await Future.wait(files.map(_downloadUrl));
    return [
      for (final url in urls)
        if (url != null) url,
    ];
  }

  /// The chosen names, or null to fall back to the folder's (none chosen).
  /// If they can't be read in time, the last answer read.
  Future<List<String>?> _chosenNames(Future<List<String>?> names, Future<ListResult> listing, int? limit) async {
    final read = ++_reads;
    try {
      return _lastChosen = await names.timeout(homePhotoNamesTimeLimit);
    } catch (e) {
      final fallback = _lastChosen;
      log('Could not read the chosen home page photos in time, so showing '
          '${fallback == null ? 'the gallery by name' : 'the last ones read'}: $e');
      if (e is TimeoutException) unawaited(_awaitLateChoice(read, names, fallback, listing, limit));
      return fallback;
    }
  }

  /// Keeps the chosen names when they answer late, and calls [onLateChoice]
  /// unless [fallback] showed those photos anyway.
  Future<void> _awaitLateChoice(
    int read,
    Future<List<String>?> names,
    List<String>? fallback,
    Future<ListResult> listing,
    int? limit,
  ) async {
    final List<String>? late;
    try {
      late = await names;
    } catch (e) {
      log('Could not read the chosen home page photos: $e');
      return;
    }
    // A newer read answers for itself.
    if (read != _reads) return;
    _lastChosen = late;
    if (late == null && fallback == null) return;
    Future<List<String>> shown(List<String>? chosen) async =>
        chosen == null ? [for (final file in _byName(await listing, limit)) file.name] : _shown(chosen, limit);
    try {
      if (listEquals(await shown(late), await shown(fallback))) return;
    } catch (_) {
      // No listing to compare with, so the folder's photos weren't shown.
    }
    onLateChoice?.call();
  }

  /// The chosen names [photoUrls] shows, up to [limit]: only photos directly
  /// in the folder (`photos` is a plain list, so the rules can't check
  /// what's in it), once each.
  static List<String> _shown(List<String> chosen, int? limit) {
    final seen = <String>{};
    final shown = [
      for (final name in chosen)
        if (!name.contains('/') && isPhoto(name) && seen.add(name)) name,
    ];
    return limit == null ? shown : shown.take(limit).toList();
  }

  /// The folder's photos by name, up to [limit].
  static List<Reference> _byName(ListResult listing, int? limit) {
    final photos = [
      for (final file in listing.items)
        if (isPhoto(file.name)) file,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return limit == null ? photos : photos.take(limit).toList();
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
