import 'package:brookie_babies/models/booking.dart';

/// A `bookings` document that [Booking.fromMap] can't read (for example a
/// typo in a hand-entered booking), with enough to find it in the Firestore
/// console.
class UnreadableBooking {
  const UnreadableBooking({required this.id, required this.problem, this.email, this.date});

  /// The document id.
  final String id;

  /// What's wrong, from [Booking.problemWith]: "date isn’t YYYY-MM-DD".
  final String problem;

  /// The document's `email` and `date` fields as typed, if they are text.
  final String? email;
  final String? date;
}

/// One session as an admin page watches it: found, deleted (or never
/// there), or there but unreadable.
sealed class SessionLookup {
  const SessionLookup();
}

class SessionFound extends SessionLookup {
  const SessionFound(this.booking);

  final Booking booking;
}

class SessionMissing extends SessionLookup {
  const SessionMissing();
}

class SessionUnreadable extends SessionLookup {
  const SessionUnreadable(this.booking);

  final UnreadableBooking booking;
}
