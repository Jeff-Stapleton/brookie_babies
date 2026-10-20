import 'package:brookie_babies/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends Fake implements FirebaseAuth {
  @override
  User? currentUser;
}

/// A signed-in user. Their token carries the [claims] they had when it was
/// issued, until a forced refresh picks up the current ones. Records each
/// token request's forceRefresh.
class _FakeUser extends Fake implements User {
  _FakeUser(this.uid, this.claims) : _tokenClaims = claims;

  @override
  final String uid;

  /// The claims on the server now.
  Map<String, dynamic>? claims;
  Map<String, dynamic>? _tokenClaims;
  final refreshes = <bool>[];

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    refreshes.add(forceRefresh);
    if (forceRefresh) _tokenClaims = claims;
    return _FakeToken(_tokenClaims);
  }
}

class _FakeToken extends Fake implements IdTokenResult {
  _FakeToken(this.claims);

  @override
  final Map<String, dynamic>? claims;
}

void main() {
  late _FakeAuth firebase;
  late FirebaseAuthService auth;

  setUp(() {
    firebase = _FakeAuth();
    auth = FirebaseAuthService(firebase);
  });

  test('signed out: not an admin, and no token to ask', () async {
    expect(await auth.isAdmin(), isFalse);
    expect(await auth.isAdmin(refresh: true), isFalse);
  });

  test('an admin is a user whose token says admin: true', () async {
    for (final (claims, admin) in [
      ({'admin': true}, true),
      ({'admin': false}, false),
      ({'admin': 'true'}, false),
      (<String, dynamic>{}, false),
      (null, false),
    ]) {
      firebase.currentUser = _FakeUser('u-$claims', claims);
      expect(await auth.isAdmin(), admin, reason: '$claims');
    }
  });

  test('the first check for each user fetches a new token; later ones use it unless asked', () async {
    final pat = _FakeUser('pat', {'admin': true});
    final sam = _FakeUser('sam', {});

    firebase.currentUser = pat;
    await auth.isAdmin();
    await auth.isAdmin();
    await auth.isAdmin(refresh: true);
    expect(pat.refreshes, [true, false, true]);

    firebase.currentUser = sam;
    await auth.isAdmin();
    await auth.isAdmin();
    expect(sam.refreshes, [true, false]);

    // Back to the first: already fresh in this app load.
    firebase.currentUser = pat;
    await auth.isAdmin();
    expect(pat.refreshes, [true, false, true, false]);
  });

  test('a claim granted since sign-in counts on the first check; a revoked one once refreshed', () async {
    final user = _FakeUser('pat', {});
    firebase.currentUser = user;
    user.claims = {'admin': true}; // scripts/grant-admin.sh, then a page refresh

    expect(await auth.isAdmin(), isTrue);

    user.claims = {}; // --revoke
    expect(await auth.isAdmin(), isTrue);
    expect(await auth.isAdmin(refresh: true), isFalse);
  });

  test('a failed first check is refreshed again next time', () async {
    final user = _FailingOnceUser('pat');
    firebase.currentUser = user;

    await expectLater(auth.isAdmin(), throwsA(isA<FirebaseAuthException>()));
    expect(await auth.isAdmin(), isTrue);
    expect(user.refreshes, [true, true]);
  });
}

class _FailingOnceUser extends _FakeUser {
  _FailingOnceUser(String uid) : super(uid, {'admin': true});

  var _failed = false;

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    if (!_failed) {
      _failed = true;
      refreshes.add(forceRefresh);
      throw FirebaseAuthException(code: 'network-request-failed');
    }
    return super.getIdTokenResult(forceRefresh);
  }
}
