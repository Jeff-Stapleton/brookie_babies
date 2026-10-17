enum BookingStatus { pending, paid, cancelled, refunded }

/// A booked photo session, from Firestore `bookings/{id}`.
///
/// Bookings are written by the server or by hand in the Firebase console;
/// customers can only read their own. See the README for the fields.
class Booking {
  const Booking({
    required this.id,
    required this.packageName,
    required this.date,
    this.time,
    this.location,
    this.status = BookingStatus.paid,
    this.photosReady = false,
  });

  final String id;
  final String packageName;

  /// Session date (midnight local time), from the `YYYY-MM-DD` field.
  final DateTime date;

  /// Start time, from the optional `HH:mm` (24-hour) field.
  final ({int hour, int minute})? time;

  final String? location;
  final BookingStatus status;

  /// Set by the photographer once every photo is uploaded.
  final bool photosReady;

  static final _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final _timePattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  /// Reads a `bookings` document. Returns null if `packageName`, `date` or
  /// `status` is missing or malformed; optional fields that are malformed are
  /// left out. Bookings are typed in by hand, so surrounding spaces and the
  /// case of `status` are forgiven.
  static Booking? fromMap(String id, Map<String, dynamic> data) {
    String text(String field) => data[field] is String ? (data[field] as String).trim() : '';

    final packageName = text('packageName');
    final dateMatch = _datePattern.firstMatch(text('date'));
    final status = BookingStatus.values.asNameMap()[text('status').toLowerCase()];
    if (packageName.isEmpty || dateMatch == null || status == null) return null;

    final date = DateTime(
      int.parse(dateMatch[1]!),
      int.parse(dateMatch[2]!),
      int.parse(dateMatch[3]!),
    );
    // DateTime normalizes invalid dates (2026-02-30 becomes March 2); reject them.
    if (date.month != int.parse(dateMatch[2]!)) return null;

    final timeMatch = _timePattern.firstMatch(text('time'));
    final location = text('location');
    return Booking(
      id: id,
      packageName: packageName,
      date: date,
      time: timeMatch == null
          ? null
          : (hour: int.parse(timeMatch[1]!), minute: int.parse(timeMatch[2]!)),
      location: location.isEmpty ? null : location,
      status: status,
      photosReady: data['photosReady'] == true,
    );
  }

  /// Whether the session was on a day before [now].
  bool isPast(DateTime now) => date.isBefore(DateTime(now.year, now.month, now.day));

  /// Sort key: date, then start time (sessions without a time sort first).
  int compareTo(Booking other) {
    final byDate = date.compareTo(other.date);
    if (byDate != 0) return byDate;
    int minutes(Booking b) => b.time == null ? -1 : b.time!.hour * 60 + b.time!.minute;
    return minutes(this).compareTo(minutes(other));
  }
}
