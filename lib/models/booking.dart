/// Firestore's `status` values. [adhoc] marks a session the photographer
/// added herself (family, friends): no purchase, so no price claim.
enum BookingStatus { pending, paid, cancelled, refunded, adhoc }

/// A booked photo session, from Firestore `bookings/{id}`.
///
/// Paid bookings are written by the server or by hand in the Firebase
/// console; ad hoc sessions by an admin in the app. Customers can only read
/// their own (by uid, or ad hoc ones shared with their Google email) and
/// ones their owner shared with them ([sharedWith]). See the README for the
/// fields.
class Booking {
  const Booking({
    required this.id,
    this.packageName,
    required this.date,
    this.time,
    this.location,
    this.status = BookingStatus.paid,
    this.photosReady = false,
    this.uid,
    this.email,
    this.emails = const [],
    this.sharedWith = const [],
    this.name,
  }) : assert(packageName != null || status == BookingStatus.adhoc, 'Only ad hoc sessions may have no package.');

  final String id;

  /// Basic, Premium or Ultimate. Every booking but an ad hoc one has one.
  final String? packageName;

  /// Session date (midnight local time), from the `YYYY-MM-DD` field.
  final DateTime date;

  /// Start time, from the optional `HH:mm` (24-hour) field.
  final ({int hour, int minute})? time;

  final String? location;
  final BookingStatus status;

  /// Set by the photographer once every photo is uploaded.
  final bool photosReady;

  /// The customer's Firebase Auth uid. Ad hoc sessions have none.
  final String? uid;

  /// On paid bookings, the email noted when it was entered. On an ad hoc
  /// session from before there could be several emails, the Google email of
  /// whoever may download the photos (see [guestEmails]).
  final String? email;

  /// An ad hoc session's `emails`: the Google emails of whoever may download
  /// the photos (see [guestEmails]).
  final List<String> emails;

  /// Who the studio shared an ad hoc session with, by Google email: its
  /// [emails], and the one [email] of a session from before there could be
  /// several (the rules and the download function let in both). None for any
  /// other booking, whose [email] is only a note.
  List<String> get guestEmails {
    if (!isAdHoc) return const [];
    final email = this.email;
    return [...emails, if (email != null && !emails.contains(email)) email];
  }

  /// Who the session's owner (the customer who booked it, or a guest of an
  /// ad hoc one) shared it with from "Your sessions", by Google email: they
  /// can see it and download its photos too, but not share it on.
  final List<String> sharedWith;

  /// An ad hoc session's name, "The Harper family", which the admin pages
  /// and the family both see as its title. On a paid booking, who it's for,
  /// shown on the Admin page only.
  final String? name;

  static final _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final _timePattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  /// "Premium session", or "Photo session" when there is no package.
  String get title => packageName == null ? 'Photo session' : '$packageName session';

  /// What "Your sessions" calls it: an ad hoc session's [name], as the
  /// admin pages do, else [title]. A paid booking's name was typed in for
  /// the Admin page, so the family sees its package.
  String get familyTitle => (isAdHoc ? name : null) ?? title;

  bool get isAdHoc => status == BookingStatus.adhoc;

  /// Whether the family can download this session's photos once they are
  /// ready: paid bookings and ad hoc sessions (getGalleryDownloadUrl's
  /// deliverable statuses).
  bool get canDeliverPhotos => status == BookingStatus.paid || status == BookingStatus.adhoc;

  /// Reads a `bookings` document. Returns null if [problemWith] finds a
  /// problem; optional fields that are malformed are left out. Paid bookings
  /// are typed in by hand, so surrounding spaces and the case of `status`
  /// are forgiven.
  static Booking? fromMap(String id, Map<String, dynamic> data) {
    if (problemWith(data) != null) return null;
    String? optional(String field) {
      final value = _text(data, field);
      return value.isEmpty ? null : value;
    }

    final dateMatch = _datePattern.firstMatch(_text(data, 'date'))!;
    final timeMatch = _timePattern.firstMatch(_text(data, 'time'));
    return Booking(
      id: id,
      packageName: optional('packageName'),
      date: DateTime(int.parse(dateMatch[1]!), int.parse(dateMatch[2]!), int.parse(dateMatch[3]!)),
      time: timeMatch == null ? null : (hour: int.parse(timeMatch[1]!), minute: int.parse(timeMatch[2]!)),
      location: optional('location'),
      status: _status(data)!,
      photosReady: data['photosReady'] == true,
      uid: optional('uid'),
      email: optional('email'),
      emails: _texts(data, 'emails'),
      sharedWith: _texts(data, 'sharedWith'),
      name: optional('name'),
    );
  }

  /// Why [fromMap] can't read [data], in a few words an admin can act on
  /// ("packageName is missing"), or null if it can.
  static String? problemWith(Map<String, dynamic> data) {
    final status = _status(data);
    if (status == null) return 'status isn’t paid, pending, cancelled, refunded or adhoc';
    if (status != BookingStatus.adhoc && _text(data, 'packageName').isEmpty) return 'packageName is missing';
    final dateMatch = _datePattern.firstMatch(_text(data, 'date'));
    if (dateMatch == null) return 'date isn’t YYYY-MM-DD';
    // DateTime normalizes invalid dates (2026-02-30 becomes March 2); reject them.
    final date = DateTime(int.parse(dateMatch[1]!), int.parse(dateMatch[2]!), int.parse(dateMatch[3]!));
    if (date.month != int.parse(dateMatch[2]!)) return 'date isn’t a real day';
    return null;
  }

  static String _text(Map<String, dynamic> data, String field) =>
      data[field] is String ? (data[field] as String).trim() : '';

  /// The text in a list [field], trimmed, without blanks; none if it isn't
  /// a list.
  static List<String> _texts(Map<String, dynamic> data, String field) => [
        if (data[field] case final List<dynamic> values)
          for (final value in values)
            if (value is String && value.trim().isNotEmpty) value.trim(),
      ];

  static BookingStatus? _status(Map<String, dynamic> data) {
    // Ad hoc sessions are only written by the app, and the rules and the
    // download function match `adhoc` exactly, so only that exact value
    // counts: a hand-typed "Adhoc " would look shared here but be shared
    // nowhere.
    if (data['status'] == BookingStatus.adhoc.name) return BookingStatus.adhoc;
    final status = BookingStatus.values.asNameMap()[_text(data, 'status').toLowerCase()];
    return status == BookingStatus.adhoc ? null : status;
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
