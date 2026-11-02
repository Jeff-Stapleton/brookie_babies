// The recording fakes below implement cloud_firestore's @sealed query types,
// as test/support/fake_firebase.dart does: Fake covers any member it adds.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_firebase.dart';
import '../support/fakes.dart';

BookingDoc _doc(String id, {String status = 'paid', String date = '2026-11-14'}) =>
    (id: id, data: {'status': status, 'packageName': 'Premium', 'date': date});

/// Records each query listened to, as its collection then its filters
/// ('uid == u1', 'emails contains a@b.co'). Anything but those filters
/// (orderBy, limit, another operator) isn't faked, so it fails the test.
class _RecordingFirestore extends Fake implements FirebaseFirestore {
  final queries = <List<String>>[];

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _RecordingQuery(this, [collectionPath]);
}

class _RecordingQuery extends Fake implements CollectionReference<Map<String, dynamic>> {
  _RecordingQuery(this._db, this._parts);

  final _RecordingFirestore _db;
  final List<String> _parts;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    final others = [
      isNotEqualTo,
      isLessThan,
      isLessThanOrEqualTo,
      isGreaterThan,
      isGreaterThanOrEqualTo,
      arrayContainsAny,
      whereIn,
      whereNotIn,
      isNull,
    ].nonNulls;
    final String filter;
    if (others.isNotEmpty || (isEqualTo == null) == (arrayContains == null)) {
      filter = '$field: not just one isEqualTo or arrayContains';
    } else {
      filter = isEqualTo != null ? '$field == $isEqualTo' : '$field contains $arrayContains';
    }
    return _RecordingQuery(_db, [..._parts, filter]);
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    _db.queries.add(_parts);
    return Stream.value(_NoDocs());
  }
}

class _NoDocs extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => const [];
}

void main() {
  // Rules aren't filters: Firestore refuses a query that asks for more than
  // firestore.rules lets the family read, and a refused shared query only
  // shows as "No sessions yet", so its exact shape is checked here.
  group('FirestoreBookingService asks for exactly what the rules allow', () {
    Future<List<List<String>>> queriesFor(AppUser user) async {
      final db = _RecordingFirestore();
      final subscription = FirestoreBookingService(db).watchBookings(user).listen(null);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      return db.queries;
    }

    test('the bookings with their uid, and the sessions shared with their email as stored', () async {
      expect(await queriesFor(const AppUser(uid: 'u1', email: ' Harper@Example.COM ')), [
        ['bookings', 'uid == u1'],
        ['bookings', 'status == adhoc', 'emails contains harper@example.com'],
        // From before a session could have several emails.
        ['bookings', 'status == adhoc', 'email == harper@example.com'],
        // Shared with them by its owner.
        ['bookings', 'sharedWith contains harper@example.com'],
      ]);
    });

    test('only the uid query without an email', () async {
      for (final email in [null, '', '  ']) {
        expect(await queriesFor(AppUser(uid: 'u1', email: email)), [
          ['bookings', 'uid == u1'],
        ], reason: '$email');
      }
    });
  });

  late StreamController<List<BookingDoc>> byUid;
  late StreamController<List<BookingDoc>> byEmail;
  late List<UserBookings> emitted;
  late List<Object> errors;

  setUp(() {
    byUid = StreamController();
    byEmail = StreamController();
    emitted = [];
    errors = [];
  });

  StreamSubscription<UserBookings> listen(Stream<UserBookings> merged) {
    final subscription = merged.listen(emitted.add, onError: errors.add);
    addTearDown(subscription.cancel);
    return subscription;
  }

  List<String> ids(UserBookings bookings) => [for (final booking in bookings.bookings) booking.id]..sort();

  test('waits for both queries, then lists them as one', () async {
    listen(mergeUserBookings(byUid.stream, asGuest: [byEmail.stream]));

    byUid.add([_doc('paid1')]);
    await pumpEventQueue();
    // Not "no shared sessions" before the shared query has answered.
    expect(emitted, isEmpty);

    byEmail.add([_doc('adhoc1', status: 'adhoc')]);
    await pumpEventQueue();
    expect(ids(emitted.single), ['adhoc1', 'paid1']);
  });

  test('every later update of either query lists them again', () async {
    listen(mergeUserBookings(byUid.stream, asGuest: [byEmail.stream]));
    byUid.add([_doc('paid1')]);
    byEmail.add([]);
    await pumpEventQueue();

    byEmail.add([_doc('adhoc1', status: 'adhoc')]);
    await pumpEventQueue();
    byUid.add([]);
    await pumpEventQueue();

    expect(emitted.map(ids), [
      ['paid1'],
      ['adhoc1', 'paid1'],
      ['adhoc1'],
    ]);
  });

  test('a booking in both queries is listed once', () async {
    listen(mergeUserBookings(byUid.stream, asGuest: [byEmail.stream]));

    byUid.add([_doc('both', status: 'adhoc')]);
    byEmail.add([_doc('both', status: 'adhoc'), _doc('bad', date: 'soon')]);
    await pumpEventQueue();

    expect(ids(emitted.last), ['both']);
    expect(emitted.last.unreadable, 1);
  });

  test('counts unreadable documents from either query, once each', () async {
    listen(mergeUserBookings(byUid.stream, asGuest: [byEmail.stream]));

    byUid.add([_doc('typo', status: 'piad'), _doc('ok')]);
    byEmail.add([_doc('typo', status: 'piad'), _doc('nodate', status: 'adhoc', date: '')]);
    await pumpEventQueue();

    expect(ids(emitted.last), ['ok']);
    expect(emitted.last.unreadable, 2);
  });

  test('the shared sessions failing (rules not deployed yet) leaves the booked ones', () async {
    listen(mergeUserBookings(byUid.stream, asGuest: [byEmail.stream]));

    byUid.add([_doc('paid1')]);
    byEmail.addError(Exception('permission-denied'));
    await pumpEventQueue();

    expect(errors, isEmpty);
    expect(ids(emitted.single), ['paid1']);

    byUid.add([_doc('paid1'), _doc('paid2')]);
    await pumpEventQueue();
    expect(ids(emitted.last), ['paid1', 'paid2']);
  });

  test('a shared query that fails after answering counts as none', () async {
    listen(mergeUserBookings(byUid.stream, asGuest: [byEmail.stream]));
    byUid.add([_doc('paid1')]);
    byEmail.add([_doc('adhoc1', status: 'adhoc')]);
    await pumpEventQueue();

    byEmail.addError(Exception('permission-denied'));
    await pumpEventQueue();

    expect(ids(emitted.last), ['paid1']);
    expect(errors, isEmpty);
  });

  group('several shared queries', () {
    late StreamController<List<BookingDoc>> byOneEmail;

    setUp(() => byOneEmail = StreamController());

    Stream<UserBookings> merged() => mergeUserBookings(byUid.stream, asGuest: [byEmail.stream, byOneEmail.stream]);

    test('waits for every one, then lists them all, each booking once', () async {
      listen(merged());

      byUid.add([_doc('paid1')]);
      byEmail.add([_doc('adhoc1', status: 'adhoc'), _doc('both', status: 'adhoc')]);
      await pumpEventQueue();
      expect(emitted, isEmpty);

      byOneEmail.add([_doc('both', status: 'adhoc'), _doc('old', status: 'adhoc')]);
      await pumpEventQueue();
      expect(ids(emitted.single), ['adhoc1', 'both', 'old', 'paid1']);
    });

    test('one failing leaves the others', () async {
      listen(merged());

      byUid.add([_doc('paid1')]);
      byEmail.addError(Exception('failed-precondition'));
      byOneEmail.add([_doc('old', status: 'adhoc')]);
      await pumpEventQueue();

      expect(errors, isEmpty);
      expect(ids(emitted.last), ['old', 'paid1']);
    });

    test('cancelling cancels them all', () async {
      var cancelled = 0;
      byEmail = StreamController(onCancel: () => cancelled++);
      byOneEmail = StreamController(onCancel: () => cancelled++);
      final subscription = listen(merged());
      await pumpEventQueue();

      await subscription.cancel();

      expect(cancelled, 2);
    });
  });

  group('shared with them by their owner', () {
    late StreamController<List<BookingDoc>> bySharedWith;

    setUp(() => bySharedWith = StreamController());

    Stream<UserBookings> merged() =>
        mergeUserBookings(byUid.stream, asGuest: [byEmail.stream], sharedWith: bySharedWith.stream);

    test('listed with the rest once it answers; the ones found only there are marked', () async {
      listen(merged());

      byUid.add([_doc('paid1')]);
      byEmail.add([_doc('adhoc1', status: 'adhoc')]);
      await pumpEventQueue();
      expect(emitted, isEmpty);

      bySharedWith.add([_doc('grandkids'), _doc('adhoc2', status: 'adhoc')]);
      await pumpEventQueue();
      expect(ids(emitted.single), ['adhoc1', 'adhoc2', 'grandkids', 'paid1']);
      expect(emitted.single.sharedWithUser, {'grandkids', 'adhoc2'});
    });

    test('one of their own that’s also shared with them is still theirs', () async {
      listen(merged());

      byUid.add([_doc('paid1')]);
      byEmail.add([_doc('adhoc1', status: 'adhoc')]);
      bySharedWith.add([_doc('paid1'), _doc('adhoc1', status: 'adhoc')]);
      await pumpEventQueue();

      expect(ids(emitted.single), ['adhoc1', 'paid1']);
      expect(emitted.single.sharedWithUser, isEmpty);
    });

    test('an unreadable one counts as unreadable, not shared', () async {
      listen(merged());

      byUid.add([]);
      byEmail.add([]);
      bySharedWith.add([_doc('typo', status: 'piad')]);
      await pumpEventQueue();

      expect(emitted.single.unreadable, 1);
      expect(emitted.single.sharedWithUser, isEmpty);
    });

    test('failing (rules not deployed yet) leaves the rest', () async {
      listen(merged());

      byUid.add([_doc('paid1')]);
      byEmail.add([_doc('adhoc1', status: 'adhoc')]);
      bySharedWith.addError(Exception('permission-denied'));
      await pumpEventQueue();

      expect(errors, isEmpty);
      expect(ids(emitted.single), ['adhoc1', 'paid1']);
    });

    test('updates live, as sessions are shared and stop being', () async {
      listen(merged());
      byUid.add([]);
      byEmail.add([]);
      bySharedWith.add([_doc('grandkids')]);
      await pumpEventQueue();

      bySharedWith.add([]);
      await pumpEventQueue();

      expect(emitted.map(ids), [
        ['grandkids'],
        <String>[],
      ]);
    });
  });

  group('FirestoreBookingService sharing', () {
    late FakeFirestore db;
    late FirestoreBookingService service;
    final booking = testSession('b1', status: BookingStatus.paid, uid: 'u1', sharedWith: ['aunt@example.com']);

    setUp(() {
      db = FakeFirestore();
      db.docs['bookings/b1'] = {'status': 'paid', 'uid': 'u1', 'packageName': 'Premium', 'date': '2999-03-04'};
      service = FirestoreBookingService(db, writeTimeLimit: const Duration(milliseconds: 50));
    });

    Matcher sharingError(Object message) => isA<SharingException>().having((e) => e.message, 'message', message);

    test('share adds the email, as stored, and changes nothing else', () async {
      await service.share(booking, ' Grandma@Example.COM ');

      expect(db.writes.single.call, 'update bookings/b1');
      expect(db.writes.single.data, {
        'sharedWith': FieldValue.arrayUnion(['grandma@example.com']),
      });
    });

    test('stopSharing takes the email out, and changes nothing else', () async {
      await service.stopSharing(booking, 'Aunt@Example.com');

      expect(db.writes.single.data, {
        'sharedWith': FieldValue.arrayRemove(['aunt@example.com']),
      });
    });

    test('share refuses what the rules would, or what changes nothing, writing nothing', () async {
      final full = testSession('b1',
          status: BookingStatus.paid, sharedWith: [for (var i = 0; i < 10; i++) 'guest$i@example.com']);
      final adHoc = testSession('a1', emails: ['harper@example.com']);
      for (final (session, email, says) in [
        (booking, '  ', 'Enter the email they use to sign in to Google.'),
        (booking, 'grandma@example', 'That isn’t a whole email address.'),
        (booking, 'grandma+kids@gmail.com', '“+kids” isn’t part of a Gmail address'),
        (booking, '${'a' * 245}@example.com', 'That’s too long for an email address'),
        (booking, ' AUNT@example.com', 'It’s already shared with aunt@example.com.'),
        (adHoc, 'harper@example.com', 'harper@example.com can already see this session.'),
        (full, 'one@more.com', 'It’s shared with 10 people, the most it can be.'),
      ]) {
        await expectLater(service.share(session, email), throwsA(sharingError(contains(says))), reason: email);
      }
      expect(db.writes, isEmpty);
    });

    test('says what happened when it fails, never the raw error', () async {
      for (final (code, says) in [
        ('permission-denied', 'We couldn’t share this session. Refresh the page and try again.'),
        ('unavailable', kSharingOfflineMessage),
        ('not-found', 'This session isn’t here any more. Refresh the page to see your sessions.'),
        ('internal', 'We couldn’t share this session. Refresh the page and try again.'),
      ]) {
        db.errors['update bookings/b1'] = FirebaseException(plugin: 'cloud_firestore', code: code);
        await expectLater(service.share(booking, 'grandma@example.com'), throwsA(sharingError(says)), reason: code);
      }
      await expectLater(
        service.stopSharing(booking, 'aunt@example.com'),
        throwsA(sharingError('We couldn’t stop sharing it. Refresh the page and try again.')),
      );
    });

    test('gives up after its time limit, saying the change may still be saved', () async {
      final hold = db.holdWrites = Completer();

      await expectLater(service.share(booking, 'grandma@example.com'), throwsA(sharingError(kSharingTimedOutMessage)));

      // A late answer isn't left uncaught.
      hold.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      await pumpEventQueue();
    });

    test('gives up after 20 seconds by default', () {
      expect(FirestoreBookingService(db).writeTimeLimit, const Duration(seconds: 20));
    });
  });

  test('the booked sessions failing is an error', () async {
    listen(mergeUserBookings(byUid.stream, asGuest: [byEmail.stream]));

    byUid.addError(Exception('permission-denied'));
    await pumpEventQueue();

    expect(errors, hasLength(1));
  });

  test('without an email there is only the uid query', () async {
    listen(mergeUserBookings(byUid.stream));

    byUid.add([_doc('paid1')]);
    await pumpEventQueue();

    expect(ids(emitted.single), ['paid1']);
  });

  test('cancelling cancels both queries', () async {
    var uidCancelled = false;
    var emailCancelled = false;
    byUid = StreamController(onCancel: () => uidCancelled = true);
    byEmail = StreamController(onCancel: () => emailCancelled = true);
    final subscription = listen(mergeUserBookings(byUid.stream, asGuest: [byEmail.stream]));
    await pumpEventQueue();
    expect(byUid.hasListener && byEmail.hasListener, isTrue);

    await subscription.cancel();

    expect(uidCancelled, isTrue);
    expect(emailCancelled, isTrue);
  });

  test('ends when the uid query ends, and stops the shared one', () async {
    var emailCancelled = false;
    byEmail = StreamController(onCancel: () => emailCancelled = true);
    final merged = mergeUserBookings(byUid.stream, asGuest: [byEmail.stream]);
    final done = Completer<void>();
    merged.listen(null, onDone: done.complete, onError: (_) {});

    await byUid.close();
    await done.future;

    expect(emailCancelled, isTrue);
  });
}
