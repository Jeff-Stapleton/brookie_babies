import 'dart:async';

import 'package:brookie_babies/services/booking_service.dart';
import 'package:flutter_test/flutter_test.dart';

BookingDoc _doc(String id, {String status = 'paid', String date = '2026-11-14'}) =>
    (id: id, data: {'status': status, 'packageName': 'Premium', 'date': date});

void main() {
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
