import 'dart:async';
import 'dart:developer';

import 'package:cloud_functions/cloud_functions.dart';

/// A link to a zip of every photo from one session.
class GalleryDownload {
  const GalleryDownload({required this.url, required this.photoCount, this.totalBytes});

  /// Signed link that expires after an hour.
  final Uri url;
  final int photoCount;

  /// The photos' total size (about the zip's); null from a function too old
  /// to say.
  final int? totalBytes;
}

/// How a zip build is going: one of getGalleryDownloadUrl's progress chunks.
///
/// Mirrors GalleryProgress in functions/src/gallery.ts; change them
/// together, adding fields only.
class GalleryProgress {
  const GalleryProgress({required this.photosDone, required this.photoCount, this.totalBytes});

  /// Photos read into the zip so far; the one being added is the next.
  final int photosDone;

  /// Photos in the zip, at least 1.
  final int photoCount;

  /// As [GalleryDownload.totalBytes].
  final int? totalBytes;

  /// Every photo is in; the server is saving the zip and signing the link.
  bool get finishing => photosDone >= photoCount;

  /// 0–1, by photos.
  double get fraction => (photosDone / photoCount).clamp(0.0, 1.0).toDouble();

  /// Null for anything but {stage: 'zipping', photosDone, photoCount} with
  /// finite, non-negative numbers and photoCount >= 1, so a newer function
  /// can't fail the download. Numbers are read as num and toInt()'d
  /// (dartify can give doubles). photosDone is clamped to photoCount. A
  /// missing, null or 0 totalBytes is unknown; any other non-number makes
  /// the chunk invalid.
  static GalleryProgress? fromChunk(Object? data) {
    if (data is! Map || data['stage'] != 'zipping') return null;
    final done = _count(data['photosDone']);
    final count = _count(data['photoCount']);
    if (done == null || count == null || count < 1) return null;
    final bytes = data['totalBytes'];
    final totalBytes = _count(bytes);
    if (bytes != null && totalBytes == null) return null;
    return GalleryProgress(
      photosDone: done > count ? count : done,
      photoCount: count,
      totalBytes: totalBytes == 0 ? null : totalBytes,
    );
  }
}

/// A finite, non-negative number from the function as an int; null for
/// anything else.
int? _count(Object? value) => value is num && value.isFinite && value >= 0 ? value.toInt() : null;

/// Hears how a zip build is going.
typedef GalleryProgressCallback = void Function(GalleryProgress progress);

/// Thrown by [GalleryService.prepareDownload] with a message to show the user.
class GalleryException implements Exception {
  const GalleryException(this.message);

  final String message;

  /// The generic message: the cause wasn't one the function explained.
  bool get isFallback => message == kGalleryErrorFallback;

  @override
  String toString() => message;
}

/// Session photo downloads. [FunctionsGalleryService] is the real
/// implementation; tests use a fake.
abstract class GalleryService {
  /// Zips the photos for [bookingId] and returns a download link. Building a
  /// large gallery's zip can take minutes; [onProgress] hears how it's going
  /// (never for a zip that's already built, or from a function that doesn't
  /// stream).
  Future<GalleryDownload> prepareDownload(String bookingId, {GalleryProgressCallback? onProgress});
}

/// Calls the `getGalleryDownloadUrl` Cloud Function, which checks that the
/// signed-in user owns the booking before returning a link. It streams:
/// progress chunks while it builds a zip, then the link.
class FunctionsGalleryService implements GalleryService {
  FunctionsGalleryService(this._functions);

  final FirebaseFunctions _functions;

  @override
  Future<GalleryDownload> prepareDownload(String bookingId, {GalleryProgressCallback? onProgress}) {
    // No options: on the web a stream ignores them (readGalleryDownload has
    // the time limit).
    final callable = _functions.httpsCallable('getGalleryDownloadUrl');
    final events = callable.stream<Object?, Object?>({'bookingId': bookingId}).map<GalleryCallEvent>(
          (response) => switch (response) {
            Chunk(:final partialData) => (isResult: false, data: partialData),
            Result(:final result) => (isResult: true, data: result.data),
          },
        );
    return readGalleryDownload(events, onProgress: onProgress);
  }
}

/// How long the site waits for a link: a minute past the function's own 9
/// (functions/src/index.ts), so the function's error normally comes first.
const kGalleryDownloadTimeLimit = Duration(minutes: 10);

/// One message from the stream: a chunk, or (isResult) the final answer.
/// Mapped to records so the logic runs on the VM (HttpsCallableResult's
/// constructor is private).
typedef GalleryCallEvent = ({bool isResult, Object? data});

/// Hands [events]' progress chunks to [onProgress] and returns the link from
/// the result. Every failure becomes a [GalleryException].
Future<GalleryDownload> readGalleryDownload(
  Stream<GalleryCallEvent> events, {
  GalleryProgressCallback? onProgress,
  Duration timeLimit = kGalleryDownloadTimeLimit,
}) async {
  var expired = false;
  Future<GalleryDownload> read() async {
    await for (final event in events) {
      // Already given up on: stop listening, and never show late progress.
      // Future.timeout ignores this error.
      if (expired) throw const GalleryException(kGalleryErrorFallback);
      if (event.isResult) return parseGalleryDownload(event.data);
      final progress = GalleryProgress.fromChunk(event.data);
      if (progress == null) continue; // A newer function's chunk, or a malformed one.
      try {
        onProgress?.call(progress);
      } catch (e) {
        // A display bug must not throw away a good download.
        log('Showing download progress failed: $e');
      }
    }
    log('getGalleryDownloadUrl ended without a result');
    throw const GalleryException(kGalleryErrorFallback);
  }

  try {
    // On the web a stream ignores HttpsCallableOptions.timeout, and the JS
    // SDK never settles one whose body ends without a result, so this is its
    // only limit. (Not webAbortSignal: its TimeLimit needs
    // AbortSignal.timeout, which Safari added only in 16.)
    return await read().timeout(timeLimit);
  } on GalleryException {
    rethrow;
  } on TimeoutException {
    expired = true;
    log('getGalleryDownloadUrl gave no result within $timeLimit');
    throw const GalleryException(kGalleryErrorFallback);
  } on FirebaseFunctionsException catch (e) {
    log('getGalleryDownloadUrl failed: ${e.code} ${e.message}');
    throw GalleryException(galleryErrorMessage(e.code, e.message));
  } catch (e) {
    log('getGalleryDownloadUrl failed: $e');
    throw const GalleryException(kGalleryErrorFallback);
  }
}

/// The result's url, photoCount and optional totalBytes (a positive number,
/// else null); [GalleryException] with [kGalleryErrorFallback] otherwise.
GalleryDownload parseGalleryDownload(Object? data) {
  if (data is Map && data['url'] is String && data['photoCount'] is num) {
    final totalBytes = _count(data['totalBytes']);
    return GalleryDownload(
      url: Uri.parse(data['url'] as String),
      photoCount: (data['photoCount'] as num).toInt(),
      totalBytes: totalBytes == 0 ? null : totalBytes,
    );
  }
  log('Unexpected getGalleryDownloadUrl response: $data');
  throw const GalleryException(kGalleryErrorFallback);
}

const kGalleryErrorFallback =
    'We couldn’t get your photos ready. Choose “Download all photos” to try again, '
    'and if it happens again, let Brooke know.';

/// The JS SDK ends every error message with the HTTP status: " [400]" from
/// a call, " [0]" from a stream.
final _statusSuffix = RegExp(r'\s*\[\d+\]$');

/// The message to show for a `getGalleryDownloadUrl` error [code]. The
/// function's own messages are only shown for `failed-precondition`, where
/// they are written for customers (without the JS SDK's status).
String galleryErrorMessage(String code, String? message) {
  switch (code) {
    case 'failed-precondition':
      final shown = message?.replaceFirst(_statusSuffix, '').trim();
      return shown == null || shown.isEmpty ? 'Your photos aren’t ready yet.' : shown;
    case 'not-found':
      return 'We couldn’t find this session’s photos. Refresh the page to try again.';
    case 'unauthenticated':
      return 'Your sign-in has expired. Sign out, sign in again, then download your photos.';
    default:
      // Includes dropped connections, the function's 9-minute limit and
      // readGalleryDownload's 10. A build whose caller left keeps going on
      // the server when Cloud Run lets it, and is cached, so a retry can be
      // quick.
      return kGalleryErrorFallback;
  }
}
