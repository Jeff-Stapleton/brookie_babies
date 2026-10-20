import 'dart:async';
import 'dart:developer';

import 'package:brookie_babies/models/picked_photo.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:flutter/foundation.dart';

/// Where one photo in an [UploadQueue] has got to.
enum UploadStatus { queued, uploading, done, skipped, failed, cancelled }

/// Starts uploading [photo] as [name]: AdminService.uploadSessionPhoto or
/// uploadToHomeLibrary, with the destination filled in.
typedef StartUpload = PhotoUpload Function(PickedPhoto photo, String name);

/// Shown for a photo whose name is already taken where it's going.
const kUploadAlreadyHere = 'Already here — to replace a photo, delete it first. Different photo with the '
    'same name? Rename it and upload it again.';

/// Shown for a photo whose name is already on its way (picked twice).
const kUploadAlreadyQueued =
    'Already in this upload. Different photo with the same name? Rename it and upload it again.';

/// Shown for a failure the admin service didn't explain.
const kUploadFailed = 'This photo didn’t upload. Use “Retry failed” to try again.';

/// One photo in an [UploadQueue]. The queue updates it in place and
/// notifies its listeners.
class UploadItem {
  UploadItem._(this.photo, this.name);

  final PickedPhoto photo;

  /// The name it's stored under: PhotoRules.safeObjectName of the file's.
  final String name;

  UploadStatus get status => _status;
  UploadStatus _status = UploadStatus.queued;

  /// 0–1 while uploading (0 until the size is known); 1 once done.
  double get progress => _progress;
  double _progress = 0;

  /// Why it failed or was skipped, written for the admin.
  String? get message => _message;
  String? _message;

  /// Whether [UploadQueue.retryFailed] would try it again: a failed upload
  /// can be retried, a photo the rules refuse can't.
  bool get canRetry => _status == UploadStatus.failed && _retryable;
  bool _retryable = false;

  bool get isFinished => _status != UploadStatus.queued && _status != UploadStatus.uploading;

  PhotoUpload? _upload;
  VoidCallback? _onProgress;

  /// Cancelled while uploading: anything but success now counts as
  /// cancelled.
  bool _cancelling = false;
}

/// Uploads picked photos a few at a time, and keeps track of each one for
/// [UploadProgressList] (lib/components/upload_progress_list.dart).
///
/// Never overwrites: a photo whose name is already in the destination, or
/// already in the queue, is skipped, so picking a whole folder again after
/// a failure is safe. Photos [validate] refuses fail without being sent.
/// Progress is reported at most every [progressInterval]; everything else
/// notifies at once. Disposing it cancels the uploads still running.
class UploadQueue extends ChangeNotifier {
  UploadQueue({
    required StartUpload upload,
    String? Function(PickedPhoto photo)? validate,
    this.onUploaded,
    this.concurrency = 3,
    this.progressInterval = const Duration(milliseconds: 250),
  })  : _startUpload = upload,
        _validate = validate;

  final StartUpload _startUpload;

  /// The reason a photo can't be uploaded (PhotoRules.sessionPhotoProblem
  /// or homePhotoProblem), or null.
  final String? Function(PickedPhoto photo)? _validate;

  /// Called as each photo is stored, so the page can add it to its list
  /// without listing the folder again.
  final void Function(UploadItem item)? onUploaded;

  /// How many photos upload at once.
  final int concurrency;

  final Duration progressInterval;

  final _items = <UploadItem>[];
  Timer? _progressTimer;
  bool _disposed = false;

  /// Every photo picked since the last [clearFinished], in the order picked.
  List<UploadItem> get items => List.unmodifiable(_items);

  /// Whether photos are still waiting or uploading.
  bool get isBusy => _items.any((item) => !item.isFinished);

  int countOf(UploadStatus status) => _items.where((item) => item.status == status).length;

  /// Whether [retryFailed] has anything to retry.
  bool get canRetry => _items.any((item) => item.canRetry);

  /// Queues [photos]. [existing] are the names in the destination, as the
  /// page lists them now; a photo with one of those names, or one already
  /// queued, is skipped. An earlier failed, skipped or cancelled try at a
  /// name gives way to the new one, and so does one stored earlier that the
  /// page no longer lists (it was deleted since).
  void add(Iterable<PickedPhoto> photos, {Iterable<String> existing = const []}) {
    // Only the page's list: it adds each stored photo through [onUploaded]
    // and drops the ones it deletes, so a photo deleted to be replaced can
    // go again.
    final here = existing.toSet();
    final taken = {
      for (final item in _items)
        if (!item.isFinished) item.name,
    };
    final picked = <String>{};
    for (final photo in photos) {
      final item = UploadItem._(photo, PhotoRules.safeObjectName(photo.name));
      if (picked.add(item.name)) {
        _items.removeWhere((old) =>
            old.name == item.name &&
            old.isFinished &&
            (old.status != UploadStatus.done || !here.contains(item.name)));
      }
      final problem = _validate?.call(photo);
      if (problem != null) {
        item
          .._status = UploadStatus.failed
          .._message = problem;
      } else if (here.contains(item.name)) {
        item
          .._status = UploadStatus.skipped
          .._message = kUploadAlreadyHere;
      } else if (!taken.add(item.name)) {
        item
          .._status = UploadStatus.skipped
          .._message = kUploadAlreadyQueued;
      }
      _items.add(item);
    }
    _pump();
    _notify();
  }

  /// Tries every failed upload again.
  void retryFailed() {
    for (final item in _items) {
      if (!item.canRetry) continue;
      item
        .._status = UploadStatus.queued
        .._progress = 0
        .._message = null;
    }
    _pump();
    _notify();
  }

  /// Stops every upload that hasn't finished: queued ones at once, running
  /// ones as soon as Storage confirms (one that finished first stays done).
  void cancelAll() {
    for (final item in _items) {
      if (item.status == UploadStatus.queued) {
        item._status = UploadStatus.cancelled;
      } else if (item.status == UploadStatus.uploading) {
        item._cancelling = true;
        item._upload?.cancel();
      }
    }
    _notify();
  }

  /// Forgets every photo that has finished, whatever the outcome.
  void clearFinished() {
    _items.removeWhere((item) => item.isFinished);
    _notify();
  }

  /// Starts queued photos, up to [concurrency] at a time.
  void _pump() {
    var running = countOf(UploadStatus.uploading);
    for (final item in _items) {
      if (running >= concurrency) return;
      if (item.status != UploadStatus.queued) continue;
      _start(item);
      // One that failed to start at all leaves its place free.
      if (item.status == UploadStatus.uploading) running++;
    }
  }

  void _start(UploadItem item) {
    item
      .._status = UploadStatus.uploading
      .._progress = 0;
    final PhotoUpload upload;
    try {
      upload = _startUpload(item.photo, item.name);
    } catch (e) {
      _finish(item, e);
      return;
    }
    item
      .._upload = upload
      .._onProgress = () {
        item._progress = upload.progress.value;
        _progressChanged();
      };
    upload.progress.addListener(item._onProgress!);
    upload.done.then((_) => _settle(item, null), onError: (Object e) => _settle(item, e));
  }

  void _settle(UploadItem item, Object? error) {
    if (_disposed) return;
    _finish(item, error);
    _pump();
    _notify();
  }

  /// Records how [item]'s upload ended: stored if [error] is null.
  void _finish(UploadItem item, Object? error) {
    final upload = item._upload;
    if (upload != null) upload.progress.removeListener(item._onProgress!);
    item
      .._upload = null
      .._onProgress = null;
    final kind = error is AdminException ? error.kind : null;
    if (error == null) {
      item
        .._status = UploadStatus.done
        .._progress = 1;
      onUploaded?.call(item);
    } else if (item._cancelling || kind == AdminErrorKind.cancelled) {
      item._status = UploadStatus.cancelled;
    } else if (kind == AdminErrorKind.alreadyExists) {
      // Stored since the page listed the folder (another tab, say).
      item
        .._status = UploadStatus.skipped
        .._message = kUploadAlreadyHere;
    } else {
      if (error is! AdminException) log('Upload of ${item.name} failed: $error');
      item
        .._status = UploadStatus.failed
        .._retryable = true
        .._message = error is AdminException ? error.message : kUploadFailed;
    }
  }

  /// Progress comes many times a second per photo; the list only needs a
  /// few frames' worth.
  void _progressChanged() {
    if (_disposed) return;
    _progressTimer ??= Timer(progressInterval, _notify);
  }

  /// Notifies now, which covers any progress still waiting to be reported.
  void _notify() {
    _progressTimer?.cancel();
    _progressTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _progressTimer?.cancel();
    for (final item in _items) {
      final upload = item._upload;
      if (upload == null) continue;
      upload.progress.removeListener(item._onProgress!);
      upload.cancel();
    }
    super.dispose();
  }
}
