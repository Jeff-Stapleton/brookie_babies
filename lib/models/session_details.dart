/// What an admin types in for an ad hoc session (a `bookings` document with
/// status `adhoc`), when adding or editing one.
class SessionDetails {
  const SessionDetails({
    required this.name,
    required this.email,
    required this.date,
    this.packageName,
    this.time,
    this.location,
  });

  /// Who it's for: "The Harper family".
  final String name;

  /// The Google email of whoever may download the photos.
  final String email;

  /// The session's day (the time of day is ignored).
  final DateTime date;

  /// Basic, Premium or Ultimate, or null for none.
  final String? packageName;

  final ({int hour, int minute})? time;
  final String? location;
}
