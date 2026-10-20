// The recording fakes below implement cloud_firestore's @sealed query types,
// as test/support/fake_firebase.dart does: Fake covers any member it adds.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

BookingDoc _doc(String id, {String status = 'paid', String date = '2026-11-14'}) =>
    (id: id, data: {'status': status, 'packageName': 'Premium', 'date': date});

/// Records each query listened to, as its collection then its filters
/// ('uid == u1'). Anything but equality filters (orderBy, limit, another
/// operator) isn't faked, so it fails the test.
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
      arrayContains,
      arrayContainsAny,
      whereIn,
      whereNotIn,
      isNull,
    ].nonNulls;
    return _RecordingQuery(_db, [..._parts, others.isEmpty ? '$field == $isEqualTo' : '$field: not only isEqualTo']);
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

    test('the bookings with their uid, and the ad hoc sessions shared with their email as stored', () async {
      expect(await queriesFor(const AppUser(uid: 'u1', email: ' Harper@Example.COM ')), [
        ['bookings', 'uid == u1'],
        ['bookings', 'status == adhoc', 'email == harper@example.com'],
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
    listen(mergeUserBookings(byUid.stream, sharedByEmail: byEmail.stream));

    byUid.add([_doc('paid1')]);
    await pumpEventQueue();
    // Not "no shared sessions" before the shared query has answered.
    expect(emitted, isEmpty);

    byEmail.add([_doc('adhoc1', status: 'adhoc')]);
    await pumpEventQueue();
    expect(ids(emitted.single), ['adhoc1', 'paid1']);
  });

  test('every later update of either query lists them again', () async {
    listen(mergeUserBookings(byUid.stream, sharedByEmail: byEmail.stream));
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
    listen(mergeUserBookings(byUid.stream, sharedByEmail: byEmail.stream));

    byUid.add([_doc('both', status: 'adhoc')]);
    byEmail.add([_doc('both', status: 'adhoc'), _doc('bad', date: 'soon')]);
    await pumpEventQueue();

    expect(ids(emitted.last), ['both']);
    expect(emitted.last.unreadable, 1);
  });

  test('counts unreadable documents from either query, once each', () async {
    listen(mergeUserBookings(byUid.stream, sharedByEmail: byEmail.stream));

    byUid.add([_doc('typo', status: 'piad'), _doc('ok')]);
    byEmail.add([_doc('typo', status: 'piad'), _doc('nodate', status: 'adhoc', date: '')]);
    await pumpEventQueue();

    expect(ids(emitted.last), ['ok']);
    expect(emitted.last.unreadable, 2);
  });

  test('the shared sessions failing (rules not deployed yet) leaves the booked ones', () async {
    listen(mergeUserBookings(byUid.stream, sharedByEmail: byEmail.stream));

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
    listen(mergeUserBookings(byUid.stream, sharedByEmail: byEmail.stream));
    byUid.add([_doc('paid1')]);
    byEmail.add([_doc('adhoc1', status: 'adhoc')]);
    await pumpEventQueue();

    byEmail.addError(Exception('permission-denied'));
    await pumpEventQueue();

    expect(ids(emitted.last), ['paid1']);
    expect(errors, isEmpty);
  });

  test('the booked sessions failing is an error', () async {
    listen(mergeUserBookings(byUid.stream, sharedByEmail: byEmail.stream));

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
    final subscription = listen(mergeUserBookings(byUid.stream, sharedByEmail: byEmail.stream));
    await pumpEventQueue();
    expect(byUid.hasListener && byEmail.hasListener, isTrue);

    await subscription.cancel();

    expect(uidCancelled, isTrue);
    expect(emailCancelled, isTrue);
  });

  test('ends when the uid query ends, and stops the shared one', () async {
    var emailCancelled = false;
    byEmail = StreamController(onCancel: () => emailCancelled = true);
    final merged = mergeUserBookings(byUid.stream, sharedByEmail: byEmail.stream);
    final done = Completer<void>();
    merged.listen(null, onDone: done.complete, onError: (_) {});

    await byUid.close();
    await done.future;

    expect(emailCancelled, isTrue);
  });
}
