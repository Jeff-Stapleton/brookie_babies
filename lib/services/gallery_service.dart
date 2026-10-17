import 'dart:developer';

import 'package:cloud_functions/cloud_functions.dart';

/// A link to a zip of every photo from one session.
class GalleryDownload {
  const GalleryDownload({required this.url, required this.photoCount});

  /// Signed link that expires after an hour.
  final Uri url;
  final int photoCount;
}

/// Thrown by [GalleryService.prepareDownload] with a message to show the user.
class GalleryException implements Exception {
  const GalleryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Session photo downloads. [FunctionsGalleryService] is the real
/// implementation; tests use a fake.
abstract class GalleryService {
  /// Zips the photos for [bookingId] and returns a download link. Can take a
  /// few minutes the first time for a large gallery.
  Future<GalleryDownload> prepareDownload(String bookingId);
}

/// Calls the `getGalleryDownloadUrl` Cloud Function, which checks that the
/// signed-in user owns the booking before returning a link.
class FunctionsGalleryService implements GalleryService {
  FunctionsGalleryService(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<GalleryDownload> prepareDownload(String bookingId) async {
    final callable = _functions.httpsCallable(
      'getGalleryDownloadUrl',
      // The function may need minutes to build the zip (its limit is 9).
      options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
    );
    try {
      final result = await callable.call<Object?>({'bookingId': bookingId});
      final data = result.data;
      if (data is Map && data['url'] is String && data['photoCount'] is num) {
        return GalleryDownload(
          url: Uri.parse(data['url'] as String),
          photoCount: (data['photoCount'] as num).toInt(),
        );
      }
      log('Unexpected getGalleryDownloadUrl response: $data');
      throw const GalleryException(kGalleryErrorFallback);
    } on FirebaseFunctionsException catch (e) {
      log('getGalleryDownloadUrl failed: ${e.code} ${e.message}');
      throw GalleryException(galleryErrorMessage(e.code, e.message));
    }
  }
}

const kGalleryErrorFallback =
    "We couldn't get your photos ready just now. Large galleries can take a "
    'few minutes, so please try again shortly.';

/// The message to show for a `getGalleryDownloadUrl` error [code]. The
/// function's own messages are only shown for `failed-precondition`, where
/// they are written for customers.
String galleryErrorMessage(String code, String? message) {
  switch (code) {
    case 'failed-precondition':
      return message ?? "Your photos aren't ready yet.";
    case 'not-found':
      return "We couldn't find this session.";
    case 'unauthenticated':
      return 'Please sign in again.';
    default:
      // Includes timeouts and dropped connections while a large zip is being
      // built; the build keeps going on the server and is cached, so a retry
      // a few minutes later is usually quick.
      return kGalleryErrorFallback;
  }
}
