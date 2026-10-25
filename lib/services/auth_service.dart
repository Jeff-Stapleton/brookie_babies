import 'dart:developer';

import 'package:brookie_babies/models/app_user.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Thrown by [AuthService.signInWithGoogle] with a message to show the user.
class SignInException implements Exception {
  const SignInException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Customer sign-in. [FirebaseAuthService] is the real implementation; tests
/// use a fake.
abstract class AuthService {
  /// Emits the user whenever they sign in or out. Use [currentUser] as the
  /// initial value; a new listener may not get one right away.
  Stream<AppUser?> get authStateChanges;

  AppUser? get currentUser;

  /// Opens the Google sign-in popup. Returns null if the user closes it.
  ///
  /// Call this first thing in a tap handler, before any `await`, or the
  /// browser may block the popup.
  Future<AppUser?> signInWithGoogle();

  Future<void> signOut();

  /// Whether the signed-in user is an admin: their ID token carries the
  /// custom claim `admin: true` (granted with scripts/grant-admin.sh). False
  /// when signed out.
  ///
  /// [refresh] fetches a new token first, so a claim granted or revoked
  /// since the token was issued counts. The rules decide what an admin can
  /// do; this only decides what the app shows.
  Future<bool> isAdmin({bool refresh = false});
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;

  /// Users whose token was refreshed since the app loaded.
  final _refreshed = <String>{};

  // A new stream per call: FirebaseAuth's stream stops working for good once
  // its last listener cancels, so it can't be cached.
  @override
  Stream<AppUser?> get authStateChanges =>
      _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  // Popup rather than redirect: on web.app the site and the auth domain
  // (firebaseapp.com) differ, which breaks redirect sign-in in current
  // browsers (only the studio's own domain signs in through itself; see
  // withSiteAuthDomain), and a redirect would reload the app and lose the
  // chosen session.
  @override
  Future<AppUser?> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    try {
      final credential = await _auth.signInWithPopup(provider);
      return _toAppUser(credential.user);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
          return null;
        case 'popup-blocked':
          throw const SignInException(
              'Your browser blocked the sign-in window. Allow pop-ups for this '
              'site, or open this page in Safari or Chrome, and try again.');
        default:
          log('Google sign-in failed: ${e.code} ${e.message}');
          throw const SignInException(
              'Sign-in failed. Please try again, or open this page in Safari '
              'or Chrome.');
      }
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  // Tokens last an hour, so a claim granted since sign-in wouldn't show until
  // then: the first check for each user after a page load fetches a new one,
  // and "refresh the page" is all a new admin needs to do.
  @override
  Future<bool> isAdmin({bool refresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final force = refresh || !_refreshed.contains(user.uid);
    final token = await user.getIdTokenResult(force);
    if (force) _refreshed.add(user.uid);
    return token.claims?['admin'] == true;
  }

  static AppUser? _toAppUser(User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
    );
  }
}
