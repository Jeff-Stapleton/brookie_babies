import 'dart:async';

import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/picked_photo.dart';
import 'package:brookie_babies/models/session_details.dart';
import 'package:brookie_babies/models/session_lookup.dart';
import 'package:brookie_babies/models/stored_photo.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_firebase.dart';
import '../support/fakes.dart';

// What firestore.rules accepts from admins in `bookings` (copied here, so a
// change to either side shows up as a failing test).
const _createKeys = {
  'status',
  'name',
  'email',
  'packageName',
  'date',
  'time',
  'location',
  'photosReady',
  'createdAt',
  'createdBy',
};
const _requiredCreateKeys = {'status', 'name', 'email', 'date', 'photosReady', 'createdAt', 'createdBy'};
const _adHocUpdateKeys = {'name', 'email', 'packageName', 'date', 'time', 'location', 'photosReady', 'updatedAt'};
const _removableKeys = {'packageName', 'time', 'location'};

const _mb = 1024 * 1024;

SessionDetails _details({
  String name = 'The Harper family',
  String email = 'harper@example.com',
  DateTime? date,
  String? packageName,
  ({int hour, int minute})? time,
  String? location,
}) =>
    SessionDetails(
      name: name,
      email: email,
      date: date ?? DateTime(2026, 11, 14),
      packageName: packageName,
      time: time,
      location: location,
    );

Matcher _adminError(AdminErrorKind kind, {Object? message}) => isA<AdminException>()
    .having((e) => e.kind, 'kind', kind)
    .having((e) => e.message, 'message', message ?? isNotEmpty);

FirebaseException _firestoreError(String code) => FirebaseException(plugin: 'cloud_firestore', code: code);

FirebaseException _storageError(String code) => FirebaseException(plugin: 'firebase_storage', code: code);

void main() {
  late List<String> log;
  late FakeFirestore db;
  late FakeStorage storage;
  late FakeFirebaseAuth auth;
  late FirebaseAdminService admin;

  setUp(() {
    log = [];
    db = FakeFirestore(log: log);
    storage = FakeStorage(log: log);
    auth = FakeFirebaseAuth(uid: 'admin-uid');
    admin = FirebaseAdminService(db, storage, auth, writeTimeLimit: const Duration(milliseconds: 50));
  });

  /// An ad hoc session as the app writes it.
  void addAdHoc(String id, {bool photosReady = false}) => db.docs['bookings/$id'] = {
        'status': 'adhoc',
        'name': 'The Harper family',
        'email': 'harper@example.com',
        'date': '2026-11-14',
        'photosReady': photosReady,
        'createdAt': FakeFirestore.serverTime,
        'createdBy': 'admin-uid',
      };

  group('errors', () {
    test('Firestore: refused is denied, no connection is offline', () {
      for (final (code, kind) in [
        ('permission-denied', AdminErrorKind.denied),
        ('unauthenticated', AdminErrorKind.denied),
        ('unavailable', AdminErrorKind.offline),
        ('deadline-exceeded', AdminErrorKind.offline),
        ('not-found', AdminErrorKind.notFound),
        ('cancelled', AdminErrorKind.cancelled),
        ('internal', AdminErrorKind.unknown),
      ]) {
        expect(adminExceptionFrom(_firestoreError(code)).kind, kind, reason: code);
      }
    });

    test('Storage: the web codes, with or without the storage/ prefix', () {
      for (final (code, kind) in [
        ('unauthorized', AdminErrorKind.denied),
        ('storage/unauthorized', AdminErrorKind.denied),
        ('unauthenticated', AdminErrorKind.denied),
        ('retry-limit-exceeded', AdminErrorKind.offline),
        ('canceled', AdminErrorKind.cancelled),
        ('object-not-found', AdminErrorKind.notFound),
        ('quota-exceeded', AdminErrorKind.quota),
        ('storage/quota-exceeded', AdminErrorKind.quota),
        ('unknown', AdminErrorKind.unknown),
      ]) {
        expect(adminExceptionFrom(_storageError(code)).kind, kind, reason: code);
      }
    });

    test('say what happened and what to do', () {
      expect(adminExceptionFrom(_firestoreError('permission-denied')).message, kAdminDeniedMessage);
      expect(adminExceptionFrom(_firestoreError('unavailable')).message, kAdminOfflineMessage);
      expect(adminExceptionFrom(_storageError('quota-exceeded')).message, kAdminQuotaMessage);
      expect(adminExceptionFrom(TimeoutException('slow')),
          _adminError(AdminErrorKind.offline, message: kAdminOfflineMessage));
    });

    test('the caller words refusals and failures it can’t explain', () {
      expect(adminExceptionFrom(_storageError('unauthorized'), denied: 'No.', failed: 'Oops.').message, 'No.');
      expect(adminExceptionFrom(_storageError('internal'), denied: 'No.', failed: 'Oops.').message, 'Oops.');
    });

    test('anything else is unknown, without the raw error', () {
      final error = adminExceptionFrom(StateError('plugin internals'));
      expect(error.kind, AdminErrorKind.unknown);
      expect(error.message, isNot(contains('plugin internals')));
    });

    test('an AdminException passes through as it is', () {
      const error = AdminException('Already explained.', AdminErrorKind.invalid);
      expect(adminExceptionFrom(error), same(error));
    });
  });

  group('sessionDetailsProblem', () {
    test('accepts what the rules accept, up to their limits', () {
      expect(
        sessionDetailsProblem(_details(
          name: 'x' * 100,
          email: ' Pat.Parent+photos@Example.COM ',
          packageName: 'Ultimate',
          date: DateTime(9999, 12, 31),
          time: (hour: 23, minute: 59),
          location: 'y' * 200,
        )),
        isNull,
      );
      expect(sessionDetailsProblem(_details(name: '  The Harper family  ', email: 'a@b.co')), isNull);
      expect(sessionDetailsProblem(_details(email: ' Pat.Parent@GoogleMail.com ')), isNull);
    });

    test('refuses an email no Google sign-in could match, though the rules would take it', () {
      for (final (email, says) in [
        ('<harper@example.com>', 'An email address has no < or >. Enter just the address, like name@gmail.com.'),
        ('mailto:harper@example.com', '“mailto:” isn’t part of the address. Enter just the address'),
        ('Pat <pat@example.com>', 'no < or >'),
        ('har per@example.com', 'That has a space in it. Take it out: an email address has none.'),
        (
          ' Pat.Parent+Photos@Gmail.com',
          '“+photos” isn’t part of a Gmail address: Google signs them in without it. Take it out.',
        ),
        ('pat+@googlemail.com', '“+” isn’t part of a Gmail address'),
      ]) {
        expect(sessionDetailsProblem(_details(email: email)), contains(says), reason: email);
      }
    });

    test('refuses what the rules refuse, saying how to fix it', () {
      for (final (details, says) in [
        (_details(name: '   '), 'Enter who the session is for'),
        (_details(name: 'x' * 101), '100 characters or fewer'),
        (_details(email: ''), 'Google email'),
        (_details(email: 'harper'), 'Google email'),
        (_details(email: 'harper@example'), 'Google email'),
        (_details(email: 'harper@@example.com'), 'Google email'),
        (_details(packageName: 'Gold'), 'Choose Basic, Premium, Ultimate or no package'),
        (_details(date: DateTime(10000)), 'Choose a date'),
        (_details(time: (hour: 24, minute: 0)), 'Choose a time'),
        (_details(time: (hour: 9, minute: 60)), 'Choose a time'),
        (_details(location: 'y' * 201), '200 characters or fewer'),
      ]) {
        expect(sessionDetailsProblem(details), contains(says), reason: '${details.name} ${details.email}');
      }
    });
  });

  group('newSessionData', () {
    test('exactly the keys the rules allow, trimmed and lowercase as they require', () {
      final data = newSessionData(
        _details(
          name: '  The Harper family ',
          email: ' Harper@Example.COM ',
          packageName: 'Premium',
          date: DateTime(2026, 3, 4, 15, 30),
          time: (hour: 9, minute: 5),
          location: ' Liberty Park ',
        ),
        createdBy: 'admin-uid',
      );

      expect(data, {
        'status': 'adhoc',
        'name': 'The Harper family',
        'email': 'harper@example.com',
        'packageName': 'Premium',
        'date': '2026-03-04',
        'time': '09:05',
        'location': 'Liberty Park',
        'photosReady': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': 'admin-uid',
      });
      expect(data.keys.toSet(), _createKeys);
    });

    test('leaves empty optional fields out: the rules refuse nulls', () {
      final data = newSessionData(_details(packageName: '', location: '   '), createdBy: 'admin-uid');

      expect(data.keys.toSet(), _requiredCreateKeys);
    });

    test('pads the date and time, and ignores the time of day', () {
      final data = newSessionData(
        _details(date: DateTime(987, 1, 2, 23, 59), time: (hour: 0, minute: 0)),
        createdBy: 'admin-uid',
      );

      expect(data['date'], '0987-01-02');
      expect(data['time'], '00:00');
    });

    test('reads back as the same session', () {
      final booking = Booking.fromMap(
        'auto-1',
        newSessionData(
          _details(packageName: 'Basic', time: (hour: 14, minute: 45), location: 'Liberty Park'),
          createdBy: 'admin-uid',
        ),
      )!;

      expect(booking.status, BookingStatus.adhoc);
      expect(booking.name, 'The Harper family');
      expect(booking.email, 'harper@example.com');
      expect(booking.packageName, 'Basic');
      expect(booking.date, DateTime(2026, 11, 14));
      expect(booking.time, (hour: 14, minute: 45));
      expect(booking.location, 'Liberty Park');
      expect(booking.photosReady, isFalse);
      expect(booking.uid, isNull);
    });
  });

  group('sessionChanges', () {
    final session = testSession(
      's1',
      date: DateTime(2026, 11, 14),
      packageName: 'Premium',
      time: (hour: 9, minute: 0),
      location: 'Liberty Park',
    );
    SessionDetails same({
      String name = 'The Harper family',
      String email = 'harper@example.com',
      DateTime? date,
      String? packageName = 'Premium',
      ({int hour, int minute})? time = (hour: 9, minute: 0),
      String? location = 'Liberty Park',
    }) =>
        _details(name: name, email: email, date: date, packageName: packageName, time: time, location: location);

    test('nothing, when only spaces, capitals or the time of day differ', () {
      expect(
        sessionChanges(
          session,
          same(name: ' The Harper family ', email: 'Harper@Example.com ', date: DateTime(2026, 11, 14, 18)),
        ),
        isEmpty,
      );
    });

    test('only the fields that changed', () {
      expect(sessionChanges(session, same(name: 'The Harpers')), {'name': 'The Harpers'});
      expect(sessionChanges(session, same(email: 'pat@example.com')), {'email': 'pat@example.com'});
      expect(sessionChanges(session, same(date: DateTime(2026, 12, 1))), {'date': '2026-12-01'});
      expect(sessionChanges(session, same(packageName: 'Basic')), {'packageName': 'Basic'});
      expect(sessionChanges(session, same(time: (hour: 10, minute: 30))), {'time': '10:30'});
      expect(sessionChanges(session, same(location: 'The studio')), {'location': 'The studio'});
    });

    test('clears optional fields with FieldValue.delete(), never null', () {
      final changes = sessionChanges(session, same(packageName: null, time: null, location: ' '));

      expect(changes, {
        'packageName': FieldValue.delete(),
        'time': FieldValue.delete(),
        'location': FieldValue.delete(),
      });
      expect(changes.keys.toSet(), _removableKeys);
    });

    test('fills in optional fields the session didn’t have', () {
      expect(
        sessionChanges(
            testSession('s2'), _details(packageName: 'Basic', time: (hour: 8, minute: 15), location: 'Home')),
        allOf(containsPair('packageName', 'Basic'), containsPair('time', '08:15'), containsPair('location', 'Home')),
      );
    });

    test('changes only what the rules let an ad hoc update change', () {
      final changes = sessionChanges(
        session,
        _details(name: 'Pat', email: 'pat@example.com', date: DateTime(2027), location: 'Home'),
      );

      expect(_adHocUpdateKeys.containsAll(changes.keys), isTrue, reason: '${changes.keys}');
    });
  });

  group('createSession', () {
    test('makes the id first, then sets exactly the new document', () async {
      final details = _details(packageName: 'Basic');

      final id = await admin.createSession(details);

      expect(id, 'auto-1');
      expect(log, ['new id bookings/auto-1', 'set bookings/auto-1']);
      expect(db.writes.single.data, newSessionData(details, createdBy: 'admin-uid'));
    });

    test('refuses what the rules would refuse, before writing', () async {
      await expectLater(admin.createSession(_details(email: 'harper')), throwsA(_adminError(AdminErrorKind.invalid)));
      expect(log, isEmpty);
    });

    test('refuses an email no guest could sign in with, before writing', () async {
      await expectLater(
        admin.createSession(_details(email: 'pat+photos@gmail.com')),
        throwsA(_adminError(AdminErrorKind.invalid, message: contains('“+photos”'))),
      );
      await expectLater(
        admin.updateSession(testSession('s1'), _details(email: '<pat@example.com>')),
        throwsA(_adminError(AdminErrorKind.invalid, message: contains('no < or >'))),
      );
      expect(log, isEmpty);
    });

    test('signed out: denied, nothing written', () async {
      auth.currentUser = null;

      await expectLater(admin.createSession(_details()), throwsA(_adminError(AdminErrorKind.denied)));
      expect(log, isEmpty);
    });

    test('refused by the rules: denied, with the spec’s message', () async {
      db.errors['set bookings/auto-1'] = _firestoreError('permission-denied');

      await expectLater(
        admin.createSession(_details()),
        throwsA(_adminError(AdminErrorKind.denied, message: kAdminDeniedMessage)),
      );
    });

    test('newSessionId makes an id without writing', () {
      expect(admin.newSessionId(), 'auto-1');
      expect(log, ['new id bookings/auto-1']);
    });

    test('with an id, sets that document', () async {
      final id = admin.newSessionId();

      expect(await admin.createSession(_details(), id: id), id);
      expect(log, ['new id bookings/$id', 'set bookings/$id']);
      expect(db.docs.keys, ['bookings/$id']);
    });

    test('a retry after a try that got no answer but was saved: the same session, not a second', () async {
      final hold = db.holdWrites = Completer();
      await expectLater(
        admin.createSession(_details(), id: 'a1'),
        throwsA(_adminError(AdminErrorKind.offline, message: kAdminTimedOutMessage)),
      );
      // The first try reaches the server after all ...
      hold.complete();
      db.holdWrites = null;
      await pumpEventQueue();
      // ... so the rules take the retry's set() as an update, and refuse it.
      db.errors['set bookings/a1'] = _firestoreError('permission-denied');

      expect(await admin.createSession(_details(), id: 'a1'), 'a1');
      expect(log, ['set bookings/a1', 'set bookings/a1', 'get bookings/a1']);
      expect(db.docs.keys, ['bookings/a1']);
    });

    test('a refused retry with no session there is still refused', () async {
      db.errors['set bookings/a1'] = _firestoreError('permission-denied');

      await expectLater(admin.createSession(_details(), id: 'a1'), throwsA(_adminError(AdminErrorKind.denied)));
      expect(log, ['set bookings/a1', 'get bookings/a1']);
    });

    test('a refused retry that can’t look either is still refused', () async {
      db.errors['set bookings/a1'] = _firestoreError('permission-denied');
      db.errors['get bookings/a1'] = _firestoreError('permission-denied');

      await expectLater(
        admin.createSession(_details(), id: 'a1'),
        throwsA(_adminError(AdminErrorKind.denied, message: kAdminDeniedMessage)),
      );
    });

    test('an id never reaches another document', () async {
      for (final id in ['', 'a/b', '..']) {
        await expectLater(admin.createSession(_details(), id: id), throwsArgumentError, reason: id);
      }
      expect(log, isEmpty);
    });
  });

  group('updateSession', () {
    test('updates only the changed fields, stamping updatedAt', () async {
      addAdHoc('s1');
      final session = testSession('s1', date: DateTime(2026, 11, 14), location: 'Liberty Park');

      await admin.updateSession(session, _details(time: (hour: 10, minute: 30)));

      expect(log, ['update bookings/s1']);
      expect(db.writes.single.data, {
        'time': '10:30',
        'location': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    test('nothing changed: nothing written', () async {
      await admin.updateSession(testSession('s1', date: DateTime(2026, 11, 14)), _details());

      expect(log, isEmpty);
    });

    test('only ad hoc sessions', () async {
      final paid = testSession('p1', status: BookingStatus.paid, date: DateTime(2026, 11, 14));

      await expectLater(admin.updateSession(paid, _details(name: 'Pat')), throwsA(_adminError(AdminErrorKind.invalid)));
      expect(log, isEmpty);
    });

    test('refuses what the rules would refuse, before writing', () async {
      await expectLater(
        admin.updateSession(testSession('s1'), _details(name: '')),
        throwsA(_adminError(AdminErrorKind.invalid)),
      );
      expect(log, isEmpty);
    });
  });

  test('setPhotosReady updates photosReady and updatedAt only', () async {
    addAdHoc('s1');

    await admin.setPhotosReady('s1', true);

    expect(log, ['update bookings/s1']);
    expect(db.writes.single.data, {'photosReady': true, 'updatedAt': FieldValue.serverTimestamp()});
    expect(db.docs['bookings/s1']!['photosReady'], isTrue);
  });

  group('writes that get no answer', () {
    test('give up after 20 seconds by default', () {
      expect(FirebaseAdminService(db, storage, auth).writeTimeLimit, const Duration(seconds: 20));
    });

    test('every one is offline, and may still have been saved', () async {
      addAdHoc('s1', photosReady: true);
      db.holdWrites = Completer();
      final writes = <String, Future<void> Function()>{
        'createSession': () => admin.createSession(_details()),
        'updateSession': () => admin.updateSession(testSession('s1'), _details(name: 'Pat')),
        'setPhotosReady': () => admin.setPhotosReady('s1', false),
        'deleteSession': () => admin.deleteSession('s1'),
        'saveHomePhotos': () => admin.saveHomePhotos(['a.jpg']),
      };

      for (final MapEntry(key: method, value: write) in writes.entries) {
        await expectLater(
          write(),
          throwsA(_adminError(AdminErrorKind.offline, message: kAdminTimedOutMessage)),
          reason: method,
        );
      }
    });

    test('a late answer isn’t left uncaught', () async {
      final hold = db.holdWrites = Completer();
      await expectLater(admin.saveHomePhotos(['a.jpg']), throwsA(_adminError(AdminErrorKind.offline)));

      hold.completeError(_firestoreError('unavailable'));
      // An uncaught error here would fail the test.
      await pumpEventQueue();
    });
  });

  group('watchSessions', () {
    setUp(() {
      addAdHoc('a');
      db.docs['bookings/b'] = {'status': 'paid', 'packageName': 'Premium', 'date': '2026-11-15', 'uid': 'u1'};
      db.docs['bookings/c'] = {'status': 'piad', 'packageName': 'Premium', 'date': 'soon', 'email': 'x@example.com'};
      db.docs['site/home'] = {'photos': <String>[]};
    });

    test('lists every booking, and names the ones that can’t be read', () async {
      final all = await admin.watchSessions().first;

      expect([for (final session in all.sessions) session.id], ['a', 'b']);
      final bad = all.unreadable.single;
      expect(bad.id, 'c');
      expect(bad.problem, Booking.problemWith(db.docs['bookings/c']!));
      expect(bad.email, 'x@example.com');
      expect(bad.date, 'soon');
    });

    test('updates live', () async {
      final emitted = <AllSessions>[];
      final subscription = admin.watchSessions().listen(emitted.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      db.docs.remove('bookings/a');
      db.notifyChanged();
      await pumpEventQueue();

      expect([for (final all in emitted) all.sessions.length], [2, 1]);
    });

    test('fails as an AdminException', () async {
      db.errors['snapshots bookings'] = _firestoreError('permission-denied');

      await expectLater(admin.watchSessions().first, throwsA(_adminError(AdminErrorKind.denied)));
    });

    test('a refused read also says the rules may not be deployed yet', () async {
      db.errors['snapshots bookings'] = _firestoreError('permission-denied');
      storage.errors['listAll galleries/s1'] = _storageError('unauthorized');
      db.errors['get site/home'] = _firestoreError('permission-denied');

      for (final read in [
        () => admin.watchSessions().first,
        () => admin.listSessionPhotos('s1'),
        () => admin.homePhotoNames(),
      ]) {
        await expectLater(read(), throwsA(_adminError(AdminErrorKind.denied, message: kAdminReadDeniedMessage)));
      }
      expect(kAdminReadDeniedMessage, contains('security rules may not be deployed yet'));
    });

    test('a failure once listening is an AdminException too', () async {
      final errors = <Object>[];
      final subscription = admin.watchSessions().listen(null, onError: errors.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      db.failStreams(_firestoreError('unavailable'));
      await pumpEventQueue();

      expect(errors, [_adminError(AdminErrorKind.offline)]);
    });
  });

  group('watchSession', () {
    test('found, unreadable or missing, live', () async {
      addAdHoc('s1');
      final emitted = <SessionLookup>[];
      final subscription = admin.watchSession('s1').listen(emitted.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      db.docs['bookings/s1']!['date'] = 'soon';
      db.notifyChanged();
      db.docs.remove('bookings/s1');
      db.notifyChanged();
      await pumpEventQueue();

      expect(emitted, [isA<SessionFound>(), isA<SessionUnreadable>(), isA<SessionMissing>()]);
      expect((emitted[0] as SessionFound).booking.name, 'The Harper family');
      expect((emitted[1] as SessionUnreadable).booking.problem, 'date isn’t YYYY-MM-DD');
    });

    test('fails as an AdminException', () async {
      db.errors['snapshots bookings/s1'] = _firestoreError('permission-denied');

      await expectLater(admin.watchSession('s1').first, throwsA(_adminError(AdminErrorKind.denied)));
    });
  });

  group('listSessionPhotos', () {
    test('walks subfolders; relative names in code-unit order, as the zip has them', () async {
      storage.objects.addAll({
        'galleries/s1/IMG_2.jpg': 'image/jpeg',
        'galleries/s1/a.jpg': 'image/jpeg',
        'galleries/s1/B.jpg': 'image/jpeg',
        'galleries/s1/edits/IMG_1.jpg': 'image/jpeg',
        'galleries/s1/edits/raw/IMG_9.heic': 'image/heic',
        'galleries/s10/not-this-session.jpg': 'image/jpeg',
        'galleries/s2/x.jpg': 'image/jpeg',
      });

      final photos = await admin.listSessionPhotos('s1');

      expect([
        for (final photo in photos) photo.name
      ], [
        'B.jpg',
        'IMG_2.jpg',
        'a.jpg',
        'edits/IMG_1.jpg',
        'edits/raw/IMG_9.heic',
      ]);
      expect(photos[3].fullPath, 'galleries/s1/edits/IMG_1.jpg');
      expect(photos.map((photo) => photo.url), everyElement(isNull));
    });

    test('leaves out hidden files and folder markers, like the download function', () async {
      storage.objects.addAll({
        'galleries/s1/a.jpg': 'image/jpeg',
        'galleries/s1/.DS_Store': null,
        'galleries/s1/edits/.hidden.jpg': 'image/jpeg',
        'galleries/s1/edits\\._IMG_1.jpg': 'image/jpeg',
        'galleries/s1/marker/': null,
      });

      final photos = await admin.listSessionPhotos('s1');

      expect([for (final photo in photos) photo.name], ['a.jpg']);
    });

    test('only lists: no metadata or links', () async {
      storage.objects['galleries/s1/edits/a.jpg'] = 'image/jpeg';

      await admin.listSessionPhotos('s1');

      expect(log, ['listAll galleries/s1', 'listAll galleries/s1/edits']);
    });

    test('never lists past the session’s own folder', () async {
      for (final id in ['', 'a/b', '..']) {
        await expectLater(admin.listSessionPhotos(id), throwsArgumentError, reason: id);
      }
      expect(log, isEmpty);
    });

    test('fails as an AdminException', () async {
      storage.errors['listAll galleries/s1'] = _storageError('unauthorized');

      await expectLater(admin.listSessionPhotos('s1'), throwsA(_adminError(AdminErrorKind.denied)));
    });
  });

  group('listHomeLibrary', () {
    test('every file directly in the folder, by name, with links for the photos', () async {
      storage.objects.addAll({
        '_admin/gallery/b.jpg': 'image/jpeg',
        '_admin/gallery/a.png': 'image/png',
        '_admin/gallery/IMG_1.HEIC': 'image/heic',
        '_admin/gallery/.DS_Store': null,
        '_admin/gallery/old/c.jpg': 'image/jpeg',
      });

      final library = await admin.listHomeLibrary();

      expect([
        for (final photo in library) (photo.name, photo.fullPath, photo.url?.toString())
      ], [
        ('.DS_Store', '_admin/gallery/.DS_Store', null),
        ('IMG_1.HEIC', '_admin/gallery/IMG_1.HEIC', null),
        ('a.png', '_admin/gallery/a.png', 'https://storage.example.com/_admin/gallery/a.png'),
        ('b.jpg', '_admin/gallery/b.jpg', 'https://storage.example.com/_admin/gallery/b.jpg'),
      ]);
      expect(
        log.where((call) => call.startsWith('getDownloadURL')),
        unorderedEquals(['getDownloadURL _admin/gallery/a.png', 'getDownloadURL _admin/gallery/b.jpg']),
      );
    });

    test('a link that can’t be fetched leaves that photo listed, without one', () async {
      storage.objects.addAll({'_admin/gallery/a.jpg': 'image/jpeg', '_admin/gallery/b.jpg': 'image/jpeg'});
      storage.errors['getDownloadURL _admin/gallery/a.jpg'] = _storageError('unknown');

      final library = await admin.listHomeLibrary();

      expect([for (final photo in library) (photo.name, photo.url != null)], [('a.jpg', false), ('b.jpg', true)]);
    });

    test('fetches a few links at a time', () async {
      for (var i = 0; i < 20; i++) {
        storage.objects['_admin/gallery/$i.jpg'] = 'image/jpeg';
      }

      final library = await admin.listHomeLibrary();

      expect(library.where((photo) => photo.url != null), hasLength(20));
      expect(storage.mostRunning, FirebaseAdminService.storageConcurrency);
    });

    test('fails as an AdminException', () async {
      storage.errors['listAll _admin/gallery'] = _storageError('retry-limit-exceeded');

      await expectLater(admin.listHomeLibrary(), throwsA(_adminError(AdminErrorKind.offline)));
    });
  });

  group('uploads', () {
    test('bytes go with putData, typed by PhotoRules', () async {
      final upload = admin.uploadSessionPhoto('s1', testPhoto('IMG_1.HEIC', contentType: ''), 'IMG_1.HEIC');

      final task = storage.tasks.single;
      expect(log, ['putData galleries/s1/IMG_1.HEIC']);
      expect(task.metadata?.contentType, 'image/heic');
      task.succeed();
      await upload.done;
      expect(storage.objects, {'galleries/s1/IMG_1.HEIC': 'image/heic'});
    });

    test('the browser’s File goes with putBlob, untouched', () {
      final file = Object();
      admin.uploadToHomeLibrary(PickedPhoto(name: 'a.JPG', size: 10, contentType: 'image/jpeg', data: file), 'a.JPG');

      final task = storage.tasks.single;
      expect(log, ['putBlob _admin/gallery/a.JPG']);
      expect(task.data, same(file));
      expect(task.metadata?.contentType, 'image/jpeg');
    });

    test('reports progress, 0 until the size is known, then 1 once stored', () async {
      final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');
      final task = storage.tasks.single;
      final seen = <double>[];
      upload.progress.addListener(() => seen.add(upload.progress.value));

      task
        ..report(0, 0)
        ..report(50, 200)
        ..report(150, 200);
      task.succeed();
      await upload.done;

      expect(seen, [0.25, 0.75, 1]);
    });

    test('a failure is an AdminException', () async {
      final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');

      storage.tasks.single.fail('quota-exceeded');

      await expectLater(upload.done, throwsA(_adminError(AdminErrorKind.quota, message: kAdminQuotaMessage)));
    });

    test('a name taken since the folder was listed is already there, not refused', () async {
      final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');
      // Stored from another tab meanwhile; the rules never overwrite.
      storage.objects['galleries/s1/a.jpg'] = 'image/jpeg';

      storage.tasks.single.fail('unauthorized');

      await expectLater(
        upload.done,
        throwsA(_adminError(
          AdminErrorKind.alreadyExists,
          message: 'Already here — to replace a photo, delete it first.',
        )),
      );
      expect(log, contains('getMetadata galleries/s1/a.jpg'));
    });

    test('refused for a name that isn’t taken: denied', () async {
      final upload = admin.uploadToHomeLibrary(testPhoto('a.jpg'), 'a.jpg');

      storage.tasks.single.fail('unauthorized');

      await expectLater(upload.done, throwsA(_adminError(AdminErrorKind.denied, message: kAdminDeniedMessage)));
    });

    test('refused, and not allowed to look either: denied', () async {
      final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');
      storage.errors['getMetadata galleries/s1/a.jpg'] = _storageError('unauthorized');

      storage.tasks.single.fail('unauthorized');

      await expectLater(upload.done, throwsA(_adminError(AdminErrorKind.denied)));
    });

    group('cancel', () {
      test('cancels the task, and ends as cancelled', () async {
        final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');
        final task = storage.tasks.single;

        upload.cancel();
        expect(task.cancelCalls, 1);
        task.fail('canceled');

        await expectLater(upload.done, throwsA(_adminError(AdminErrorKind.cancelled)));
      });

      test('however the task then ends, short of success', () async {
        final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');

        upload.cancel();
        storage.tasks.single.fail('unknown');

        await expectLater(upload.done, throwsA(_adminError(AdminErrorKind.cancelled)));
      });

      test('a photo that got there first stays uploaded', () async {
        final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');

        upload.cancel();
        storage.tasks.single.succeed();

        await upload.done;
      });

      test('cancel’s own failure isn’t left uncaught', () async {
        final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');
        storage.tasks.single.cancelError = _storageError('unknown');

        upload.cancel();
        // An uncaught error here would fail the test.
        await pumpEventQueue();
      });

      test('does nothing once it has finished', () async {
        final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');
        final task = storage.tasks.single..succeed();
        await upload.done;

        upload.cancel();

        expect(task.cancelCalls, 0);
      });
    });

    test('refuses what the rules would refuse, sending nothing', () async {
      final refused = <(PhotoUpload, Object)>[
        (
          admin.uploadSessionPhoto('s1', testPhoto('notes.txt', contentType: 'text/plain'), 'notes.txt'),
          'notes.txt isn’t a photo.',
        ),
        (admin.uploadSessionPhoto('s1', testPhoto('big.jpg', size: 100 * _mb), 'big.jpg'), contains('100 MB')),
        (
          admin.uploadToHomeLibrary(testPhoto('IMG_1.HEIC', contentType: 'image/heic'), 'IMG_1.HEIC'),
          contains('isn’t a JPEG, PNG or WebP'),
        ),
        (admin.uploadToHomeLibrary(testPhoto('a.jpg', size: 20 * _mb), 'a.jpg'), contains('20 MB')),
        (admin.uploadToHomeLibrary(testPhoto('a.jpg'), 'a'), contains('needs a .jpg, .png or .webp ending')),
        (admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'x/a.jpg'), contains('can’t be used as a file name')),
      ];

      for (final (upload, message) in refused) {
        await expectLater(upload.done, throwsA(_adminError(AdminErrorKind.invalid, message: message)));
      }
      expect(log, isEmpty);
    });

    test('signed out: denied, sending nothing', () async {
      auth.currentUser = null;

      final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');

      await expectLater(upload.done, throwsA(_adminError(AdminErrorKind.denied)));
      expect(log, isEmpty);
    });

    test('a task that fails to start fails done, without throwing', () async {
      storage.errors['putData galleries/s1/a.jpg'] = StateError('plugin internals');

      final upload = admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');

      await expectLater(upload.done, throwsA(_adminError(AdminErrorKind.unknown, message: contains('didn’t upload'))));
    });

    test('never outside the session’s own folder', () async {
      final upload = admin.uploadSessionPhoto('', testPhoto('a.jpg'), 'a.jpg');

      await expectLater(upload.done, throwsA(isA<AdminException>()));
      expect(log, isEmpty);
    });

    test('listens to the task’s events, and a failure nobody waits for isn’t uncaught', () async {
      admin.uploadSessionPhoto('s1', testPhoto('notes.txt', contentType: 'text/plain'), 'notes.txt');
      admin.uploadSessionPhoto('s1', testPhoto('a.jpg'), 'a.jpg');
      final task = storage.tasks.single;
      expect(task.isWatched, isTrue);

      task.fail('unknown');
      // An uncaught error here would fail the test.
      await pumpEventQueue();
      expect(task.isWatched, isFalse);
    });
  });

  group('deletePhoto', () {
    const photo = StoredPhoto(name: 'edits/a.jpg', fullPath: 'galleries/s1/edits/a.jpg');

    test('deletes it', () async {
      storage.objects[photo.fullPath] = 'image/jpeg';

      await admin.deletePhoto(photo);

      expect(log, ['delete galleries/s1/edits/a.jpg']);
      expect(storage.objects, isEmpty);
    });

    test('one already gone counts as deleted', () async {
      await admin.deletePhoto(photo);
    });

    test('fails as an AdminException', () async {
      storage.objects[photo.fullPath] = 'image/jpeg';
      storage.errors['delete galleries/s1/edits/a.jpg'] = _storageError('unauthorized');

      await expectLater(
          admin.deletePhoto(photo), throwsA(_adminError(AdminErrorKind.denied, message: kAdminDeniedMessage)));
    });

    test('signed out: denied, nothing deleted', () async {
      auth.currentUser = null;

      await expectLater(admin.deletePhoto(photo), throwsA(_adminError(AdminErrorKind.denied)));
      expect(log, isEmpty);
    });
  });

  group('deleteSession', () {
    setUp(() {
      storage.objects.addAll({
        'galleries/s1/a.jpg': 'image/jpeg',
        'galleries/s1/.DS_Store': null,
        'galleries/s1/edits/b.jpg': 'image/jpeg',
        'gallery-zips/s1.zip': 'application/zip',
        'galleries/s10/keep.jpg': 'image/jpeg',
        'gallery-zips/s10.zip': 'application/zip',
      });
    });

    /// The log without the listing.
    List<String> changes() => [
          for (final call in log)
            if (!call.startsWith('listAll ')) call,
        ];

    test('hides the photos, deletes every file and the zip, then the document', () async {
      addAdHoc('s1', photosReady: true);

      await admin.deleteSession('s1');

      final calls = changes();
      expect(calls.take(2), ['get bookings/s1', 'update bookings/s1']);
      expect(
          calls.sublist(2, 5),
          unorderedEquals([
            'delete galleries/s1/a.jpg',
            'delete galleries/s1/.DS_Store',
            'delete galleries/s1/edits/b.jpg',
          ]));
      expect(calls.skip(5), ['delete gallery-zips/s1.zip', 'delete bookings/s1']);
      expect(db.writes.first.data, {'photosReady': false, 'updatedAt': FieldValue.serverTimestamp()});
      expect(db.docs, isEmpty);
      expect(storage.objects.keys, unorderedEquals(['galleries/s10/keep.jpg', 'gallery-zips/s10.zip']));
    });

    test('photos not available: nothing to hide', () async {
      addAdHoc('s1');

      await admin.deleteSession('s1');

      expect(log, isNot(contains('update bookings/s1')));
      expect(db.docs, isEmpty);
    });

    test('no zip, or files already gone: still deleted', () async {
      addAdHoc('s1');
      storage.objects.clear();

      await admin.deleteSession('s1');

      expect(changes(), ['get bookings/s1', 'delete gallery-zips/s1.zip', 'delete bookings/s1']);
      expect(db.docs, isEmpty);
    });

    test('already deleted: done, touching nothing', () async {
      await admin.deleteSession('s1');

      expect(log, ['get bookings/s1']);
      expect(storage.objects, hasLength(6));
    });

    test('only ad hoc sessions', () async {
      db.docs['bookings/s1'] = {'status': 'paid', 'packageName': 'Premium', 'date': '2026-11-14', 'uid': 'u1'};

      await expectLater(admin.deleteSession('s1'), throwsA(_adminError(AdminErrorKind.invalid)));
      expect(log, ['get bookings/s1']);
      expect(storage.objects, hasLength(6));
    });

    test('a file that won’t delete stops it there, the photos hidden', () async {
      addAdHoc('s1', photosReady: true);
      storage.errors['delete galleries/s1/edits/b.jpg'] = _storageError('unauthorized');

      await expectLater(admin.deleteSession('s1'), throwsA(_adminError(AdminErrorKind.denied)));
      expect(db.docs['bookings/s1']!['photosReady'], isFalse);
      expect(log, isNot(contains('delete gallery-zips/s1.zip')));
      expect(log, isNot(contains('delete bookings/s1')));
    });

    test('deletes a few files at a time', () async {
      addAdHoc('s1');
      for (var i = 0; i < 20; i++) {
        storage.objects['galleries/s1/$i.jpg'] = 'image/jpeg';
      }

      await admin.deleteSession('s1');

      expect(storage.mostRunning, FirebaseAdminService.storageConcurrency);
      expect(storage.objects.keys.where((path) => path.startsWith('galleries/s1/')), isEmpty);
    });

    test('a refused read is denied, deleting nothing', () async {
      addAdHoc('s1');
      db.errors['get bookings/s1'] = _firestoreError('permission-denied');

      await expectLater(admin.deleteSession('s1'), throwsA(_adminError(AdminErrorKind.denied)));
      expect(storage.objects, hasLength(6));
    });

    test('signed out: denied, nothing deleted', () async {
      addAdHoc('s1');
      auth.currentUser = null;

      await expectLater(admin.deleteSession('s1'), throwsA(_adminError(AdminErrorKind.denied)));
      expect(log, isEmpty);
    });

    test('never outside the session’s own folder', () async {
      await expectLater(admin.deleteSession(''), throwsArgumentError);
      expect(log, isEmpty);
    });
  });

  group('homePhotoNames', () {
    test('null until chosen', () async {
      expect(await admin.homePhotoNames(), isNull);
      expect(log, ['get site/home']);
    });

    test('the chosen names, in order', () async {
      db.docs['site/home'] = {
        'photos': ['b.jpg', 'a.jpg'],
      };

      expect(await admin.homePhotoNames(), ['b.jpg', 'a.jpg']);
    });

    test('skips anything but text', () async {
      db.docs['site/home'] = {
        'photos': ['b.jpg', 3, null, 'a.jpg'],
      };

      expect(await admin.homePhotoNames(), ['b.jpg', 'a.jpg']);
    });

    test('null when photos isn’t a list', () async {
      for (final data in [
        {'photos': 'a.jpg'},
        <String, dynamic>{},
      ]) {
        db.docs['site/home'] = data;
        expect(await admin.homePhotoNames(), isNull, reason: '$data');
      }
    });

    test('fails as an AdminException', () async {
      db.errors['get site/home'] = _firestoreError('unavailable');

      await expectLater(admin.homePhotoNames(), throwsA(_adminError(AdminErrorKind.offline)));
    });
  });

  group('saveHomePhotos', () {
    test('sets exactly photos, updatedAt and updatedBy', () async {
      await admin.saveHomePhotos(['b.jpg', 'a.jpg']);

      expect(log, ['set site/home']);
      expect(db.writes.single.data, {
        'photos': ['b.jpg', 'a.jpg'],
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': 'admin-uid',
      });
      expect(await admin.homePhotoNames(), ['b.jpg', 'a.jpg']);
    });

    test('none at all is a choice too', () async {
      await admin.saveHomePhotos([]);

      expect(db.docs['site/home']!['photos'], isEmpty);
    });

    test('at most seven', () async {
      await admin.saveHomePhotos([for (var i = 0; i < 7; i++) '$i.jpg']);

      await expectLater(
        admin.saveHomePhotos([for (var i = 0; i < 8; i++) '$i.jpg']),
        throwsA(_adminError(AdminErrorKind.invalid, message: contains('at most 7'))),
      );
      expect(log, ['set site/home']);
    });

    test('only names directly in the library', () async {
      for (final name in ['old/a.jpg', '']) {
        await expectLater(admin.saveHomePhotos(['b.jpg', name]), throwsA(_adminError(AdminErrorKind.invalid)));
      }
      expect(log, isEmpty);
    });

    test('signed out: denied, nothing written', () async {
      auth.currentUser = null;

      await expectLater(admin.saveHomePhotos(['a.jpg']), throwsA(_adminError(AdminErrorKind.denied)));
      expect(log, isEmpty);
    });
  });
}
