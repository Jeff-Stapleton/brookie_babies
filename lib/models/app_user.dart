/// The signed-in customer.
///
/// Mirrors the parts of Firebase's `User` the app uses, so widgets and tests
/// don't depend on Firebase types.
class AppUser {
  const AppUser({required this.uid, this.email, this.displayName});

  /// Firebase Auth uid: the key that links purchases (and later photos) to a
  /// customer.
  final String uid;
  final String? email;
  final String? displayName;

  /// First letter of the name or email, for the account avatar.
  String get initial {
    final name = displayName?.trim() ?? '';
    final source = name.isNotEmpty ? name : (email ?? '');
    return source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
  }
}
