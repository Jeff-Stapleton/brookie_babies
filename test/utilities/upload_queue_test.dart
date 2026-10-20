import 'package:brookie_babies/components/upload_progress_list.dart';
import 'package:brookie_babies/models/picked_photo.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/utilities/upload_queue.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// An upload that ignores cancel(): it ended before Storage heard.
class _TooLateToCancel implements PhotoUpload {
  final _upload = FakePhotoUpload(fullPath: 'galleries/s1/late.jpg', photo: testPhoto('late.jpg'), name: 'late.jpg');
  var cancelCalls = 0;

  void complete() => _upload.complete();

  void fail(AdminErrorKind kind) => _upload.fail(kind);

  @override
  ValueListenable<double> get progress => _upload.progress;

  @override
  Future<void> get done => _upload.done;

  @override
  void cancel() => cancelCalls++;
}

void main() {
  late FakeAdminService admin;
  late List<UploadItem> uploaded;
  late UploadQueue queue;

  UploadQueue newQueue({Duration progressInterval = Duration.zero}) => UploadQueue(
        upload: (photo, name) => admin.uploadSessionPhoto('s1', photo, name),
        validate: PhotoRules.sessionPhotoProblem,
        onUploaded: uploaded.add,
        progressInterval: progressInterval,
      );

  setUp(() {
    admin = FakeAdminService();
    uploaded = [];
    queue = newQueue();
  });

  tearDown(() => queue.dispose());

  List<PickedPhoto> photos(int count) => [for (var i = 1; i <= count; i++) testPhoto('IMG_$i.jpg')];
  List<UploadStatus> statuses() => [for (final item in queue.items) item.status];
  UploadItem item(String name) => queue.items.singleWhere((item) => item.name == name);

  test('uploads three at a time, in the order picked', () async {
    queue.add(photos(5));

    expect(admin.uploads.map((u) => u.name), ['IMG_1.jpg', 'IMG_2.jpg', 'IMG_3.jpg']);
    expect(statuses(), [
      UploadStatus.uploading,
      UploadStatus.uploading,
      UploadStatus.uploading,
      UploadStatus.queued,
      UploadStatus.queued,
    ]);
    expect(queue.isBusy, isTrue);

    admin.uploads[1].complete();
    await pumpEventQueue();

    expect(item('IMG_2.jpg').status, UploadStatus.done);
    expect(admin.uploads.map((u) => u.name), ['IMG_1.jpg', 'IMG_2.jpg', 'IMG_3.jpg', 'IMG_4.jpg']);
    expect(queue.countOf(UploadStatus.uploading), 3);

    for (final upload in admin.pendingUploads) {
      upload.complete();
    }
    await pumpEventQueue();
    for (final upload in admin.pendingUploads) {
      upload.complete();
    }
    await pumpEventQueue();

    expect(statuses(), everyElement(UploadStatus.done));
    expect(queue.isBusy, isFalse);
    expect(admin.sessionPhotos['s1'], hasLength(5));
  });

  test('reports progress, then 1 when done, and tells the page about each stored photo', () async {
    queue.add(photos(1));

    admin.uploads.single.setProgress(0.4);
    expect(item('IMG_1.jpg').progress, 0.4);

    admin.uploads.single.complete();
    await pumpEventQueue();

    expect(item('IMG_1.jpg').progress, 1);
    expect(uploaded.map((item) => item.name), ['IMG_1.jpg']);
  });

  test('uploads under the safe name', () {
    queue.add([testPhoto('Harper #1.jpg')]);

    expect(admin.uploads.single.fullPath, 'galleries/s1/Harper _1.jpg');
    expect(queue.items.single.name, 'Harper _1.jpg');
    expect(queue.items.single.photo.name, 'Harper #1.jpg');
  });

  group('never overwrites', () {
    test('a name already in the destination is skipped, and says how to replace it', () {
      queue.add(photos(2), existing: ['IMG_2.jpg']);

      expect(item('IMG_2.jpg').status, UploadStatus.skipped);
      expect(item('IMG_2.jpg').message, kUploadAlreadyHere);
      expect(admin.uploads.map((u) => u.name), ['IMG_1.jpg']);
    });

    test('a name picked twice at once is uploaded once', () {
      // Both become 'a_.jpg'.
      queue.add([testPhoto('a#.jpg'), testPhoto('a?.jpg'), testPhoto('a*.jpg')]);

      expect(statuses(), [UploadStatus.uploading, UploadStatus.skipped, UploadStatus.skipped]);
      expect(queue.items[1].message, kUploadAlreadyQueued);
      expect(admin.uploads, hasLength(1));
    });

    test('a name still on its way from an earlier pick is skipped', () {
      queue.add(photos(5));

      queue.add([testPhoto('IMG_5.jpg')]);

      expect(queue.items.last.status, UploadStatus.skipped);
      expect(queue.items.last.message, kUploadAlreadyQueued);
      expect(queue.countOf(UploadStatus.queued), 2);
    });

    test('a name uploaded earlier is skipped while the page still lists it', () async {
      queue.add(photos(1));
      admin.uploads.single.complete();
      await pumpEventQueue();

      queue.add(photos(2), existing: ['IMG_1.jpg']);

      expect(queue.items.where((item) => item.name == 'IMG_1.jpg').map((item) => item.status),
          [UploadStatus.done, UploadStatus.skipped]);
      expect(queue.items.last.name, 'IMG_2.jpg');
      expect(admin.uploads.map((u) => u.name), ['IMG_1.jpg', 'IMG_2.jpg']);
    });

    test('a photo deleted since it was uploaded can go again, and replaces its entry', () async {
      queue.add(photos(2));
      for (final upload in admin.pendingUploads) {
        upload.complete();
      }
      await pumpEventQueue();
      // "Delete all photos": the page lists neither now.
      admin.sessionPhotos['s1']!.clear();

      queue.add(photos(2));

      expect(queue.items.map((item) => (item.name, item.status)), [
        ('IMG_1.jpg', UploadStatus.uploading),
        ('IMG_2.jpg', UploadStatus.uploading),
      ]);
      expect(admin.uploads, hasLength(4));
      expect(uploadSummary(queue), 'Uploading 0 of 2');
    });

    test('stored since the page listed it (another tab): skipped, not failed, and the page hears of it', () async {
      admin.sessionPhotos['s1'] = ['IMG_1.jpg'];

      queue.add(photos(1));
      await pumpEventQueue();

      expect(item('IMG_1.jpg').status, UploadStatus.skipped);
      expect(item('IMG_1.jpg').message, kUploadAlreadyHere);
      expect(uploaded.map((item) => item.name), ['IMG_1.jpg']);
    });

    test('a retry of a photo that got through without saying so is skipped, and the page hears of it', () async {
      queue.add(photos(1));
      // Stored on the server, but the browser gave up waiting.
      admin.sessionPhotos['s1'] = ['IMG_1.jpg'];
      admin.uploads.single.fail(AdminErrorKind.offline);
      await pumpEventQueue();
      expect(uploaded, isEmpty);

      queue.retryFailed();
      await pumpEventQueue();

      expect(item('IMG_1.jpg').status, UploadStatus.skipped);
      expect(uploaded.map((item) => item.name), ['IMG_1.jpg']);
    });

    test('found already there as it was cancelled: skipped, not cancelled, and the page hears of it', () async {
      final refused = _TooLateToCancel();
      final racing = UploadQueue(upload: (photo, name) => refused, onUploaded: uploaded.add);
      addTearDown(racing.dispose);
      racing.add([testPhoto('late.jpg')]);

      racing.cancelAll();
      refused.fail(AdminErrorKind.alreadyExists);
      await pumpEventQueue();

      expect(racing.items.single.status, UploadStatus.skipped);
      expect(uploaded, hasLength(1));
    });
  });

  group('validation', () {
    test('a photo the rules would refuse fails with the reason and is never sent', () {
      queue.add([testPhoto('notes.txt', contentType: 'text/plain'), testPhoto('IMG_1.jpg', size: 0)]);

      expect(statuses(), [UploadStatus.failed, UploadStatus.failed]);
      expect(queue.items[0].message, 'notes.txt isn’t a photo.');
      expect(queue.items[1].message, 'IMG_1.jpg is empty.');
      expect(admin.uploads, isEmpty);
      expect(queue.isBusy, isFalse);
    });

    test('isn’t retried: it would only fail again', () {
      queue.add([testPhoto('notes.txt', contentType: 'text/plain')]);

      expect(queue.canRetry, isFalse);
      expect(queue.items.single.canRetry, isFalse);
      queue.retryFailed();

      expect(queue.items.single.status, UploadStatus.failed);
      expect(admin.uploads, isEmpty);
    });

    test('a refused photo doesn’t hold its name: the same name can still upload', () {
      queue.add([testPhoto('IMG_1.jpg', size: 0), testPhoto('IMG_1.jpg')]);

      expect(statuses(), [UploadStatus.failed, UploadStatus.uploading]);
    });
  });

  group('failures', () {
    test('fail with the service’s message, and can be retried', () async {
      queue.add(photos(2));
      admin.uploads[0].fail(AdminErrorKind.offline);
      admin.uploads[1].complete();
      await pumpEventQueue();

      expect(item('IMG_1.jpg').status, UploadStatus.failed);
      expect(item('IMG_1.jpg').message, kAdminOfflineMessage);
      expect(item('IMG_1.jpg').canRetry, isTrue);
      expect(queue.canRetry, isTrue);
      expect(queue.isBusy, isFalse);

      queue.retryFailed();

      expect(item('IMG_1.jpg').status, UploadStatus.uploading);
      expect(item('IMG_1.jpg').message, isNull);
      expect(admin.uploads, hasLength(3));
      admin.uploads.last.complete();
      await pumpEventQueue();
      expect(statuses(), [UploadStatus.done, UploadStatus.done]);
      expect(uploaded.map((item) => item.name), ['IMG_2.jpg', 'IMG_1.jpg']);
    });

    test('an error the service didn’t explain gets a general message', () async {
      queue.add(photos(1));
      admin.uploads.single.failWith(Exception('socket closed'));
      await pumpEventQueue();

      expect(item('IMG_1.jpg').status, UploadStatus.failed);
      expect(item('IMG_1.jpg').message, kUploadFailed);
    });

    test('an upload that can’t even start fails, and the rest still go', () async {
      var calls = 0;
      final failing = UploadQueue(
        upload: (photo, name) {
          if (++calls <= 3) throw StateError('no bucket');
          return admin.uploadSessionPhoto('s1', photo, name);
        },
      );
      addTearDown(failing.dispose);

      failing.add(photos(5));

      expect([for (final item in failing.items) item.status], [
        UploadStatus.failed,
        UploadStatus.failed,
        UploadStatus.failed,
        UploadStatus.uploading,
        UploadStatus.uploading,
      ]);
      expect(failing.items.first.message, kUploadFailed);
    });

    test('picking a failed photo again replaces the failed entry', () async {
      queue.add(photos(2));
      admin.uploads[0].fail(AdminErrorKind.offline);
      admin.uploads[1].complete();
      await pumpEventQueue();

      // The whole folder again: the stored one is skipped, the failed one goes.
      queue.add(photos(2), existing: ['IMG_2.jpg']);

      expect(queue.items.map((item) => (item.name, item.status)), [
        ('IMG_2.jpg', UploadStatus.done),
        ('IMG_1.jpg', UploadStatus.uploading),
        ('IMG_2.jpg', UploadStatus.skipped),
      ]);
    });
  });

  group('cancelling', () {
    test('stops queued photos at once and running ones as Storage confirms: cancelled, not failed', () async {
      queue.add(photos(5));

      queue.cancelAll();

      expect(admin.uploads.every((upload) => upload.cancelled), isTrue);
      expect(statuses().skip(3), everyElement(UploadStatus.cancelled));
      await pumpEventQueue();

      expect(statuses(), everyElement(UploadStatus.cancelled));
      expect(queue.isBusy, isFalse);
      expect(queue.canRetry, isFalse);
      expect(admin.uploads, hasLength(3));
    });

    test('a photo that finished before the cancel arrived stays done', () async {
      final finishing = _TooLateToCancel();
      final racing = UploadQueue(upload: (photo, name) => finishing, onUploaded: uploaded.add);
      addTearDown(racing.dispose);
      racing.add([testPhoto('late.jpg')]);

      racing.cancelAll();
      finishing.complete();
      await pumpEventQueue();

      expect(finishing.cancelCalls, 1);
      expect(racing.items.single.status, UploadStatus.done);
      expect(uploaded, hasLength(1));
    });

    test('a cancel reported as an error counts as cancelled', () async {
      queue.add(photos(1));
      admin.uploads.single.fail(AdminErrorKind.cancelled);
      await pumpEventQueue();

      expect(item('IMG_1.jpg').status, UploadStatus.cancelled);
    });
  });

  test('clearFinished forgets finished photos, whatever the outcome, and keeps the rest', () async {
    queue.add([...photos(5), testPhoto('notes.txt', contentType: 'text/plain')], existing: ['IMG_5.jpg']);
    admin.uploads[0].complete();
    admin.uploads[1].fail(AdminErrorKind.offline);
    await pumpEventQueue();

    queue.clearFinished();

    expect(queue.items.map((item) => item.name), ['IMG_3.jpg', 'IMG_4.jpg']);
    expect(queue.items.map((item) => item.status), everyElement(UploadStatus.uploading));
  });

  test('counts each outcome', () async {
    queue.add([...photos(4), testPhoto('notes.txt', contentType: 'text/plain')], existing: ['IMG_4.jpg']);
    admin.uploads[0].complete();
    admin.uploads[1].fail(AdminErrorKind.offline);
    await pumpEventQueue();

    expect(queue.countOf(UploadStatus.done), 1);
    expect(queue.countOf(UploadStatus.failed), 2);
    expect(queue.countOf(UploadStatus.skipped), 1);
    expect(queue.countOf(UploadStatus.uploading), 1);
    expect(queue.countOf(UploadStatus.queued), 0);
  });

  test('disposing it cancels the uploads still running and ignores their ends', () async {
    final disposable = newQueue();
    disposable.add(photos(4));
    var notified = 0;
    disposable.addListener(() => notified++);

    disposable.dispose();
    await pumpEventQueue();

    expect(admin.uploads, hasLength(3));
    expect(admin.uploads.every((upload) => upload.cancelled), isTrue);
    expect(notified, 0);
    expect(uploaded, isEmpty);
  });

  group('notifications', () {
    test('every change of status notifies at once', () async {
      var notified = 0;
      queue.addListener(() => notified++);

      queue.add(photos(1));
      expect(notified, 1);

      admin.uploads.single.complete();
      await pumpEventQueue();
      expect(notified, 2);

      queue.clearFinished();
      expect(notified, 3);
    });

    test('progress is gathered up: one notification per interval, however many updates', () async {
      final throttled = newQueue(progressInterval: const Duration(milliseconds: 40));
      addTearDown(throttled.dispose);
      throttled.add(photos(3));
      var notified = 0;
      throttled.addListener(() => notified++);

      for (var i = 1; i <= 10; i++) {
        for (final upload in admin.uploads) {
          upload.setProgress(i / 10);
        }
      }
      expect(notified, 0);
      // The items are current even before the notification.
      expect(throttled.items.first.progress, 1);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(notified, 1);

      admin.uploads.first.setProgress(0.5);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(notified, 2);
    });
  });
}
