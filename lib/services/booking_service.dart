import 'dart:async';
import 'dart:developer';

import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// A user's bookings, plus how many of their booking documents couldn't be
/// read (for example a typo in a hand-entered booking), so the page can say
/// so instead of silently leaving a session out.
typedef UserBookings = ({List<Booking> bookings, int unreadable});

/// One `bookings` document, as a query returns it.
typedef BookingDoc = ({String id, Map<String, dynamic> data});

/// The signed-in customer's bookings. [FirestoreBookingService] is the real
/// implementation; tests use a fake.
abstract class BookingService {
  /// [user]'s bookings, updated live, in no particular order: the ones booked
  /// with their uid, and ad hoc sessions shared with their email.
  Stream<UserBookings> watchBookings(AppUser user);
}

class FirestoreBookingService implements BookingService {
  FirestoreBookingService(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<UserBookings> watchBookings(AppUser user) {
    // Security rules only let customers read their own bookings, and rules
    // aren't filters, so each query has to ask for exactly what the rules
    // allow. Equality filters only, so neither needs a composite index.
    final bookings = _db.collection('bookings');
    Stream<List<BookingDoc>> docs(Query<Map<String, dynamic>> query) => query
        .snapshots()
        .map((snapshot) => [for (final doc in snapshot.docs) (id: doc.id, data: doc.data())]);

    // As the session stores it (firestore.rules lowercases the token's).
    final email = SessionRules.normalizeEmail(user.email ?? '');
    final adHoc = bookings.where('status', isEqualTo: BookingStatus.adhoc.name);
    return mergeUserBookings(
      docs(bookings.where('uid', isEqualTo: user.uid)),
      sharedByEmail: email.isEmpty
          ? const []
          : [
              docs(adHoc.where('emails', arrayContains: email)),
              // Sessions from before there could be several emails.
              docs(adHoc.where('email', isEqualTo: email)),
            ],
    );
  }
}

/// The bookings in [byUid] and each of [sharedByEmail] as one live list,
/// each document once (a document in more than one is the same booking).
///
/// The first list waits until every query has answered, so a guest's
/// sessions don't pop in after "No sessions yet"; then every update to any
/// re-emits. One of [sharedByEmail] failing (say, before rules that allow
/// it are deployed) is logged and counts as no sessions from it, so it never
/// hides the family's own bookings or the other shared ones; [byUid] failing
/// is an error. Cancelling the result cancels every query.
@visibleForTesting
Stream<UserBookings> mergeUserBookings(
  Stream<List<BookingDoc>> byUid, {
  List<Stream<List<BookingDoc>>> sharedByEmail = const [],
}) {
  late final StreamController<UserBookings> controller;
  StreamSubscription<List<BookingDoc>>? own;
  final shared = <StreamSubscription<List<BookingDoc>>>[];
  List<BookingDoc>? ownDocs;
  // Null until that query answers.
  final sharedDocs = List<List<BookingDoc>?>.filled(sharedByEmail.length, null);

  void emit() {
    final ownSoFar = ownDocs;
    if (ownSoFar == null || sharedDocs.contains(null)) return;
    final seen = <String>{};
    final bookings = <Booking>[];
    var unreadable = 0;
    for (final doc in [...ownSoFar, for (final docs in sharedDocs) ...?docs]) {
      if (!seen.add(doc.id)) continue;
      final booking = Booking.fromMap(doc.id, doc.data);
      if (booking == null) {
        unreadable++;
        log('Skipping malformed booking ${doc.id}: ${Booking.problemWith(doc.data)}');
      } else {
        bookings.add(booking);
      }
    }
    controller.add((bookings: bookings, unreadable: unreadable));
  }

  controller = StreamController<UserBookings>(
    onListen: () {
      own = byUid.listen(
        (docs) {
          ownDocs = docs;
          emit();
        },
        onError: controller.addError,
        // Firestore ends a query's stream only after an error, and the
        // shared sessions alone aren't the family's list.
        onDone: () {
          for (final subscription in shared) {
            subscription.cancel();
          }
          controller.close();
        },
      );
      for (final (i, query) in sharedByEmail.indexed) {
        shared.add(query.listen(
          (docs) {
            sharedDocs[i] = docs;
            emit();
          },
          onError: (Object error) {
            // Never the email itself: it's personal.
            log('Could not load some sessions shared by email, so leaving them out: $error');
            sharedDocs[i] = const [];
            emit();
          },
        ));
      }
    },
    onPause: () {
      own?.pause();
      for (final subscription in shared) {
        subscription.pause();
      }
    },
    onResume: () {
      own?.resume();
      for (final subscription in shared) {
        subscription.resume();
      }
    },
    onCancel: () async {
      await own?.cancel();
      for (final subscription in shared) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}
