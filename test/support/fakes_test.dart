// The fakes other tests drive, behaving as their docs say.

import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_details.dart';
import 'package:brookie_babies/models/session_lookup.dart';
import 'package:brookie_babies/models/stored_photo.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  final harper = SessionDetails(
    name: ' The Harper family ',
    email: ' Harper@Example.com ',
    date: DateTime(2026, 11, 14, 15),
    packageName: 'Premium',
  );

  group('FakeAdminService', () {
    test('live sessions emit now and again on every change', () async {
      final admin = FakeAdminService(sessions: [testSession('s1', status: BookingStatus.paid)]);
      final seen = <List<String>>[];
      final subscription = admin.watchSessions().listen((all) => seen.add([for (final s in all.sessions) s.id]));
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      final id = await admin.createSession(harper);
      await admin.setPhotosReady('s1', true);
      await admin.deleteSession(id);
      await pumpEventQueue();

      expect(seen, [
        ['s1'],
        ['s1', id],
        ['s1', id],
        ['s1'],
      ]);
      expect(admin.calls, [
        'watchSessions()',
        'createSession(The Harper family)',
        'setPhotosReady(s1, true)',
        'deleteSession($id)',
      ]);
    });

    test('new sessions are ad hoc, normalized like the real service', () async {
      final admin = FakeAdminService();

      final id = await admin.createSession(harper);

      final session = admin.sessions[id]!;
      expect(session.status, BookingStatus.adhoc);
      expect(session.name, 'The Harper family');
      expect(session.email, 'harper@example.com');
      expect(session.date, DateTime(2026, 11, 14));
      expect(session.photosReady, isFalse);
      expect(session.uid, isNull);
    });

    test('createSession with an id already saved finds it, and never makes a second', () async {
      final admin = FakeAdminService();
      final id = admin.newSessionId();
      final other = SessionDetails(name: 'Other', email: 'o@example.com', date: DateTime(2027));

      expect(await admin.createSession(harper, id: id), id);
      expect(await admin.createSession(other, id: id), id);

      expect(admin.sessions.keys, [id]);
      expect(admin.sessions[id]!.name, 'The Harper family');
      expect(admin.createSessionIds, [id, id]);
    });

    test('one session: found, unreadable, or missing once deleted', () async {
      final admin = FakeAdminService(
        sessions: [testSession('s1')],
        unreadable: [const UnreadableBooking(id: 'bad', problem: 'date isn’t YYYY-MM-DD')],
      );
      final seen = <SessionLookup>[];
      admin.watchSession('s1').listen(seen.add);
      final bad = await admin.watchSession('bad').first;
      await pumpEventQueue();

      await admin.deleteSession('s1');
      await pumpEventQueue();

      expect(seen.first, isA<SessionFound>());
      expect(seen.last, isA<SessionMissing>());
      expect((bad as SessionUnreadable).booking.problem, 'date isn’t YYYY-MM-DD');
    });

    test('a session that isn’t there: changes refused as the rules refuse them, deleting it done', () async {
      final admin = FakeAdminService();
      final refused = throwsA(isA<AdminException>()
          .having((e) => e.kind, 'kind', AdminErrorKind.denied)
          .having((e) => e.message, 'message', kAdminDeniedMessage));

      await expectLater(admin.setPhotosReady('gone', true), refused);
      await expectLater(admin.updateSession(testSession('gone'), harper), refused);
      await admin.deleteSession('gone');

      expect(admin.sessions, isEmpty);
    });

    test('nextError fails one call; errors fail every call to a method', () async {
      final admin = FakeAdminService(sessions: [testSession('s1')])
        ..nextError = adminError(AdminErrorKind.offline)
        ..errors['listSessionPhotos'] = adminError(AdminErrorKind.denied);

      await expectLater(admin.setPhotosReady('s1', true),
          throwsA(isA<AdminException>().having((e) => e.kind, 'kind', AdminErrorKind.offline)));
      await admin.setPhotosReady('s1', true);
      expect(admin.sessions['s1']!.photosReady, isTrue);

      for (var i = 0; i < 2; i++) {
        await expectLater(admin.listSessionPhotos('s1'),
            throwsA(isA<AdminException>().having((e) => e.message, 'message', kAdminDeniedMessage)));
      }
    });

    test('live streams fail on cue', () async {
      final admin = FakeAdminService()..watchError = adminError(AdminErrorKind.denied);
      await expectLater(admin.watchSessions(), emitsError(isA<AdminException>()));

      admin.watchError = null;
      final errors = <Object>[];
      admin.watchSessions().listen(null, onError: errors.add);
      admin.failLiveStreams(adminError(AdminErrorKind.offline));
      await pumpEventQueue();
      expect(errors, hasLength(1));
    });

    test('a live stream that fails ends there, as Firestore’s do', () async {
      final admin = FakeAdminService(sessions: [testSession('s1')]);
      final seen = <String>[];
      var done = false;
      admin.watchSession('s1').listen(
            (lookup) => seen.add('value'),
            onError: (Object _) => seen.add('error'),
            onDone: () => done = true,
          );
      await pumpEventQueue();

      admin.failLiveStreams(adminError(AdminErrorKind.denied));
      admin.notifyChanged();
      await pumpEventQueue();

      expect(seen, ['value', 'error']);
      expect(done, isTrue);
      // Others listen afresh.
      expect(await admin.watchSession('s1').first, isA<SessionFound>());
    });

    test('writes take writeDelay', () async {
      final admin = FakeAdminService(sessions: [testSession('s1')])
        ..writeDelay = const Duration(milliseconds: 30);
      var done = false;

      final write = admin.setPhotosReady('s1', true).then((_) => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(done, isFalse);
      await write;
      expect(done, isTrue);
    });

    test('uploads run until the test finishes them, then land in the folder', () async {
      final admin = FakeAdminService();
      final photo = testPhoto('IMG_1.jpg');

      final upload = admin.uploadSessionPhoto('s1', photo, 'IMG_1.jpg') as FakePhotoUpload;
      expect(upload.fullPath, 'galleries/s1/IMG_1.jpg');
      upload.setProgress(0.5);
      expect(upload.progress.value, 0.5);
      expect(admin.pendingUploads, [upload]);

      upload.complete();
      await upload.done;
      expect(upload.progress.value, 1);
      expect(admin.sessionPhotos['s1'], ['IMG_1.jpg']);
      expect((await admin.listSessionPhotos('s1')).single.fullPath, 'galleries/s1/IMG_1.jpg');
    });

    test('uploads fail with any kind, and cancel as cancelled', () async {
      final admin = FakeAdminService();
      final failing = admin.uploadToHomeLibrary(testPhoto('a.jpg'), 'a.jpg') as FakePhotoUpload;
      final cancelled = admin.uploadToHomeLibrary(testPhoto('b.jpg'), 'b.jpg');

      failing.fail(AdminErrorKind.quota);
      cancelled.cancel();

      await expectLater(
          failing.done, throwsA(isA<AdminException>().having((e) => e.kind, 'kind', AdminErrorKind.quota)));
      await expectLater(
          cancelled.done, throwsA(isA<AdminException>().having((e) => e.kind, 'kind', AdminErrorKind.cancelled)));
      expect(admin.library, isEmpty);
    });

    test('never overwrites: a name already there fails as alreadyExists', () async {
      final admin = FakeAdminService(library: ['a.jpg']);

      final upload = admin.uploadToHomeLibrary(testPhoto('a.jpg'), 'a.jpg');

      await expectLater(
          upload.done, throwsA(isA<AdminException>().having((e) => e.kind, 'kind', AdminErrorKind.alreadyExists)));
    });

    test('autoCompleteUploads finishes them at once', () async {
      final admin = FakeAdminService(autoCompleteUploads: true);

      await admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg').done;

      expect(admin.sessionPhotos['s1'], ['a.jpg']);
    });

    test('the home library: links for photos only, deletes, and the chosen names', () async {
      final admin = FakeAdminService(library: ['b.jpg', 'a.HEIC'], sessionPhotos: {
        's1': ['z.jpg', 'edits/a.jpg'],
      });

      final library = await admin.listHomeLibrary();
      expect(library.map((p) => (p.name, p.url != null)), [('a.HEIC', false), ('b.jpg', true)]);
      expect(await admin.homePhotoNames(), isNull);

      await admin.saveHomePhotos(['b.jpg']);
      expect(await admin.homePhotoNames(), ['b.jpg']);

      await admin.deletePhoto(library.first);
      await admin.deletePhoto(const StoredPhoto(name: 'edits/a.jpg', fullPath: 'galleries/s1/edits/a.jpg'));
      expect(admin.library, ['b.jpg']);
      expect((await admin.listSessionPhotos('s1')).map((p) => p.name), ['z.jpg']);
    });
  });

  test('FakePhotoPicker hands back what the test chose, and records what was asked for', () async {
    final picker = FakePhotoPicker()..next = [testPhoto('a.jpg')];

    expect((await picker(accept: 'image/*')).single.name, 'a.jpg');
    expect(picker.accepts, ['image/*']);
  });

  test('FakeAuthService answers held admin checks one at a time', () async {
    final auth = FakeAuthService(signedInAs: testUser, admin: true)..holdIsAdmin = true;
    final first = auth.isAdmin(refresh: true);
    final second = auth.isAdmin();

    auth.answerIsAdmin();
    expect(await first, isTrue);
    auth
      ..admin = false
      ..answerIsAdmin();
    expect(await second, isFalse);
    expect(auth.isAdminCalls, [true, false]);
  });
}
