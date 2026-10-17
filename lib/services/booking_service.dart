import 'dart:developer';

import 'package:brookie_babies/models/booking.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A user's bookings, plus how many of their booking documents couldn't be
/// read (for example a typo in a hand-entered booking), so the page can say
/// so instead of silently leaving a session out.
typedef UserBookings = ({List<Booking> bookings, int unreadable});

/// The signed-in customer's bookings. [FirestoreBookingService] is the real
/// implementation; tests use a fake.
abstract class BookingService {
  /// [uid]'s bookings, updated live, in no particular order.
  Stream<UserBookings> watchBookings(String uid);
}

class FirestoreBookingService implements BookingService {
  FirestoreBookingService(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<UserBookings> watchBookings(String uid) {
    // Security rules only let customers read their own bookings, and rules
    // aren't filters, so the query has to ask for exactly those.
    return _db
        .collection('bookings')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final bookings = <Booking>[];
      var unreadable = 0;
      for (final doc in snapshot.docs) {
        final booking = Booking.fromMap(doc.id, doc.data());
        if (booking == null) {
          unreadable++;
          log('Skipping malformed booking ${doc.id}');
        } else {
          bookings.add(booking);
        }
      }
      return (bookings: bookings, unreadable: unreadable);
    });
  }
}
