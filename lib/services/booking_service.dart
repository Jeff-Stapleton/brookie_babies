import 'dart:async';
import 'dart:developer';

import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// A user's bookings, plus how many of their booking documents couldn't be
/// read (for example a typo in a hand-entered booking), so the page can say
/// so instead of silently leaving a session out, and the ids of the ones
/// they see only because someone shared it with them ([Booking.sharedWith]):
/// theirs to download, not to share on.
typedef UserBookings = ({List<Booking> bookings, int unreadable, Set<String> sharedWithUser});

/// One `bookings` document, as a query returns it.
typedef BookingDoc = ({String id, Map<String, dynamic> data});

/// Thrown by [BookingService.share] and [BookingService.stopSharing] with a
/// message to show the family.
class SharingException implements Exception {
  const SharingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A share or stop that got no answer in time: it may still reach the server.
const kSharingTimedOutMessage =
    'We couldn’t reach the server in time. Your change may still be saved: refresh the page to check.';

const kSharingOfflineMessage = 'We couldn’t reach the server. Check your connection and try again.';

/// The signed-in customer's bookings, and who they share them with.
/// [FirestoreBookingService] is the real implementation; tests use a fake.
abstract class BookingService {
  /// [user]'s bookings, updated live, in no particular order: the ones booked
  /// with their uid, ad hoc sessions shared with their email, and sessions
  /// their owner shared with it.
  Stream<UserBookings> watchBookings(AppUser user);

  /// Shares [booking], one of the user's own, with [email]: whoever signs in
  /// to Google as it sees the session and can download its photos. Checked
  /// with [sharingProblem] first. Fails with [SharingException].
  Future<void> share(Booking booking, String email);

  /// Stops sharing [booking] with [email]. Fails with [SharingException].
  Future<void> stopSharing(Booking booking, String email);
}

class FirestoreBookingService implements BookingService {
  FirestoreBookingService(this._db, {this.writeTimeLimit = const Duration(seconds: 20)});

  final FirebaseFirestore _db;

  /// How long a share may take before the family is told it may not have
  /// been saved: offline, the web SDK waits for the server with no limit.
  final Duration writeTimeLimit;

  CollectionReference<Map<String, dynamic>> get _bookings => _db.collection('bookings');

  @override
  Stream<UserBookings> watchBookings(AppUser user) {
    // Security rules only let customers read their own bookings, and rules
    // aren't filters, so each query has to ask for exactly what the rules
    // allow. Equality and arrayContains filters only, so none needs a
    // composite index.
    Stream<List<BookingDoc>> docs(Query<Map<String, dynamic>> query) => query
        .snapshots()
        .map((snapshot) => [for (final doc in snapshot.docs) (id: doc.id, data: doc.data())]);

    // As the session stores it (firestore.rules lowercases the token's).
    final email = SessionRules.normalizeEmail(user.email ?? '');
    final adHoc = _bookings.where('status', isEqualTo: BookingStatus.adhoc.name);
    return mergeUserBookings(
      docs(_bookings.where('uid', isEqualTo: user.uid)),
      asGuest: email.isEmpty
          ? const []
          : [
              docs(adHoc.where('emails', arrayContains: email)),
              // Sessions from before there could be several emails.
              docs(adHoc.where('email', isEqualTo: email)),
            ],
      sharedWith: email.isEmpty ? null : docs(_bookings.where('sharedWith', arrayContains: email)),
    );
  }

  @override
  Future<void> share(Booking booking, String email) async {
    final problem = sharingProblem(booking, email);
    if (problem != null) throw SharingException(problem);
    await _changeSharing(
      booking,
      FieldValue.arrayUnion([SessionRules.normalizeEmail(email)]),
      failed: 'We couldn’t share this session. Refresh the page and try again.',
    );
  }

  @override
  Future<void> stopSharing(Booking booking, String email) => _changeSharing(
        booking,
        FieldValue.arrayRemove([SessionRules.normalizeEmail(email)]),
        failed: 'We couldn’t stop sharing it. Refresh the page and try again.',
      );

  /// Applies [change] to [booking]'s sharedWith, the one field its owner may
  /// write (firestore.rules), giving up after [writeTimeLimit]. One email at
  /// a time, so two of a couple sharing at once never undo each other.
  Future<void> _changeSharing(Booking booking, FieldValue change, {required String failed}) async {
    try {
      await _bookings.doc(booking.id).update({'sharedWith': change}).timeout(writeTimeLimit);
    } on TimeoutException {
      log('Sharing: no answer in ${writeTimeLimit.inSeconds} s for booking ${booking.id}');
      throw const SharingException(kSharingTimedOutMessage);
    } catch (e) {
      // Never the email itself: it's personal.
      log('Sharing booking ${booking.id} failed: $e');
      throw SharingException(switch (e is FirebaseException ? e.code.split('/').last : null) {
        'unavailable' || 'deadline-exceeded' => kSharingOfflineMessage,
        'not-found' => 'This session isn’t here any more. Refresh the page to see your sessions.',
        _ => failed,
      });
    }
  }
}

/// Why [booking] can't be shared with [email], written for the family: the
/// rules would refuse it (validEmailList), no Google sign-in could match it,
/// or it changes nothing. Null if it can be. Change the rules and this
/// together.
String? sharingProblem(Booking booking, String email) {
  final normalized = SessionRules.normalizeEmail(email);
  if (normalized.isEmpty) return 'Enter the email they use to sign in to Google.';
  final problem = SessionRules.emailProblem(normalized);
  if (problem != null) return problem;
  if (booking.sharedWith.contains(normalized)) return 'It’s already shared with $normalized.';
  if (booking.guestEmails.contains(normalized)) return '$normalized can already see this session.';
  if (booking.sharedWith.length >= SessionRules.emailListMaxLength) {
    return 'It’s shared with ${SessionRules.emailListMaxLength} people, the most it can be. Stop sharing with '
        'someone to add another.';
  }
  return null;
}

/// The bookings in [byUid], each of [asGuest] and [sharedWith] as one live
/// list, each document once (a document in more than one is the same
/// booking). Those found only by [sharedWith] are in `sharedWithUser`.
///
/// The first list waits until every query has answered, so a guest's
/// sessions don't pop in after "No sessions yet"; then every update to any
/// re-emits. One of [asGuest] or [sharedWith] failing (say, before rules that
/// allow it are deployed) is logged and counts as no sessions from it, so it
/// never hides the family's own bookings or the other shared ones; [byUid]
/// failing is an error. Cancelling the result cancels every query.
@visibleForTesting
Stream<UserBookings> mergeUserBookings(
  Stream<List<BookingDoc>> byUid, {
  List<Stream<List<BookingDoc>>> asGuest = const [],
  Stream<List<BookingDoc>>? sharedWith,
}) {
  final sharedByEmail = [...asGuest, if (sharedWith != null) sharedWith];
  late final StreamController<UserBookings> controller;
  StreamSubscription<List<BookingDoc>>? own;
  final shared = <StreamSubscription<List<BookingDoc>>>[];
  List<BookingDoc>? ownDocs;
  // Null until that query answers.
  final sharedDocs = List<List<BookingDoc>?>.filled(sharedByEmail.length, null);

  void emit() {
    final ownSoFar = ownDocs;
    if (ownSoFar == null || sharedDocs.contains(null)) return;
    // Theirs to share: booked with their uid, or shared with them by the
    // studio. (The rules' isOwner.)
    final owned = {
      for (final doc in [...ownSoFar, for (final docs in sharedDocs.take(asGuest.length)) ...?docs]) doc.id,
    };
    final seen = <String>{};
    final bookings = <Booking>[];
    final sharedWithUser = <String>{};
    var unreadable = 0;
    for (final doc in [...ownSoFar, for (final docs in sharedDocs) ...?docs]) {
      if (!seen.add(doc.id)) continue;
      final booking = Booking.fromMap(doc.id, doc.data);
      if (booking == null) {
        unreadable++;
        log('Skipping malformed booking ${doc.id}: ${Booking.problemWith(doc.data)}');
      } else {
        bookings.add(booking);
        if (!owned.contains(doc.id)) sharedWithUser.add(doc.id);
      }
    }
    controller.add((bookings: bookings, unreadable: unreadable, sharedWithUser: sharedWithUser));
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
