import 'package:brookie_babies/components/admin_gate.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _studio = AppUser(uid: 'studio', email: 'studio@example.com', displayName: 'Brooke');

const _signedOutText = 'Sign in with the studio’s Google account to manage sessions and photos.';
const _notAdminText =
    'This account (parent@example.com) isn’t an admin. Sign out and sign in with the studio’s Google account.';
const _errorText = 'We couldn’t check your access. Refresh the page to try again.';

/// Signed in as the studio, with a token that says [cached] about the
/// admin claim. A fresh one says [admin], or fails with [refreshError].
class _TokenAuth extends FakeAuthService {
  _TokenAuth({required this.cached, super.admin, this.refreshError}) : super(signedInAs: _studio);

  final bool cached;
  final Object? refreshError;

  @override
  Future<bool> isAdmin({bool refresh = false}) {
    if (refresh && refreshError != null) {
      isAdminCalls.add(refresh);
      return Future.error(refreshError!);
    }
    if (refresh) return super.isAdmin(refresh: true);
    isAdminCalls.add(refresh);
    return Future.value(cached);
  }
}

void main() {
  Future<void> pumpGate(
    WidgetTester tester,
    FakeAuthService auth, {
    Brightness brightness = Brightness.light,
    Size size = const Size(1440, 900),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(
      auth: auth,
      brightness: brightness,
      home: const Scaffold(body: AdminGate(child: Text('Admin only'))),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets('signed out: asks for the studio’s account, with its own "Sign in"', (tester) async {
    await pumpGate(tester, FakeAuthService());

    expect(find.text(_signedOutText), findsOneWidget);
    expect(find.text('Admin only'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInDialog), findsOneWidget);
  });

  testWidgets('signing in from the gate checks the new account', (tester) async {
    final auth = FakeAuthService(admin: true)..nextSignIn = _studio;
    await pumpGate(tester, auth);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text('Admin only'), findsOneWidget);
    expect(auth.isAdminCalls, [false]);
  });

  testWidgets('an admin sees the page on the token the app has, with no fresh one to wait for', (tester) async {
    final auth = FakeAuthService(signedInAs: _studio, admin: true);
    await pumpGate(tester, auth);

    expect(find.text('Admin only'), findsOneWidget);
    expect(auth.isAdminCalls, [false]);
  });

  testWidgets('a “no” is checked again with a fresh token, so someone just made an admin gets in', (tester) async {
    final auth = _TokenAuth(cached: false, admin: true);
    await pumpGate(tester, auth);

    expect(find.text('Admin only'), findsOneWidget);
    expect(auth.isAdminCalls, [false, true]);
  });

  testWidgets('a “no” that can’t be checked again says to refresh', (tester) async {
    await pumpGate(tester, _TokenAuth(cached: false, admin: true, refreshError: Exception('offline')));

    expect(find.widgetWithText(InlineMessage, _errorText), findsOneWidget);
    expect(find.text('Admin only'), findsNothing);
  });

  testWidgets('while checking: a spinner, and not the page', (tester) async {
    final auth = FakeAuthService(signedInAs: _studio, admin: true)..holdIsAdmin = true;
    await pumpGate(tester, auth, settle: false);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Admin only'), findsNothing);

    auth.answerIsAdmin();
    await tester.pumpAndSettle();
    expect(find.text('Admin only'), findsOneWidget);
  });

  testWidgets('a failed check says to refresh', (tester) async {
    await pumpGate(tester, FakeAuthService(signedInAs: _studio, admin: true)..isAdminError = Exception('offline'));

    expect(find.widgetWithText(InlineMessage, _errorText), findsOneWidget);
    expect(find.text('Admin only'), findsNothing);
  });

  testWidgets('anyone else: names the account and offers "Sign out"', (tester) async {
    final auth = FakeAuthService(signedInAs: testUser);
    await pumpGate(tester, auth);

    expect(find.text(_notAdminText), findsOneWidget);
    expect(find.text('Admin only'), findsNothing);
    expect(auth.isAdminCalls, [false, true]);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(auth.currentUser, isNull);
    expect(find.text(_signedOutText), findsOneWidget);
  });

  testWidgets('an account without an email is still told what to do', (tester) async {
    await pumpGate(tester, FakeAuthService(signedInAs: const AppUser(uid: 'u2')));

    expect(
      find.text('This account isn’t an admin. Sign out and sign in with the studio’s Google account.'),
      findsOneWidget,
    );
  });

  testWidgets('switching accounts checks the new one', (tester) async {
    final auth = FakeAuthService(signedInAs: testUser)..nextSignIn = _studio;
    await pumpGate(tester, auth);
    expect(find.text(_notAdminText), findsOneWidget);

    auth.admin = true;
    await auth.signInWithGoogle();
    await tester.pumpAndSettle();

    expect(find.text('Admin only'), findsOneWidget);
    expect(auth.isAdminCalls, [false, true, false]);
  });

  // Every state the gate shows on its own, in both themes, on a phone and a
  // wide screen, with the color its words come in.
  final states = <String, (FakeAuthService Function(), String?, Color Function(BrookieColors))>{
    'signed out': (FakeAuthService.new, _signedOutText, (c) => c.ink),
    'checking': (() => FakeAuthService(signedInAs: _studio)..holdIsAdmin = true, null, (c) => c.ink),
    'check failed': (
      () => FakeAuthService(signedInAs: _studio)..isAdminError = Exception('offline'),
      _errorText,
      (c) => c.danger,
    ),
    'not an admin': (() => FakeAuthService(signedInAs: testUser), _notAdminText, (c) => c.ink),
  };
  for (final MapEntry(key: state, value: (auth, text, color)) in states.entries) {
    for (final brightness in Brightness.values) {
      for (final width in [320.0, 1440.0]) {
        testWidgets('$state, ${brightness.name}, ${width.toInt()}px: fits, in the theme’s colors', (tester) async {
          await pumpGate(tester, auth(), brightness: brightness, size: Size(width, 800), settle: false);
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byType(FilledButton).evaluate().length, lessThanOrEqualTo(1));
          final colors = brightness == Brightness.dark ? BrookieColors.dark : BrookieColors.light;
          if (text == null) {
            final spinner = find.byType(CircularProgressIndicator);
            expect(tester.widget<CircularProgressIndicator>(spinner).color ??
                Theme.of(tester.element(spinner)).progressIndicatorTheme.color, color(colors));
            return;
          }
          final shown = find.text(text);
          expect(shown, findsOneWidget);
          expect(tester.renderObject<RenderParagraph>(shown).text.style!.color, color(colors));
          // Held to the reading width, in the page's gutter.
          expect(tester.getSize(shown).width, lessThanOrEqualTo(BrookieSize.readingWidth));
          expect(tester.getTopLeft(shown).dx, greaterThanOrEqualTo(BrookieSpace.s4));
        });
      }
    }
  }
}
