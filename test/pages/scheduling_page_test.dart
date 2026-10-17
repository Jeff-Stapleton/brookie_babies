import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/widgets/session_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeUrlOpener urlOpener;

  Future<void> pumpPage(WidgetTester tester, FakeAuthService auth, {String packageName = 'Premium'}) async {
    // The session cards have fixed widths, so use a desktop-sized window.
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(testApp(
      auth: auth,
      urlOpener: urlOpener,
      home: SchedulingPage(packageName: packageName),
    ));
  }

  Future<void> tapFirstSession(WidgetTester tester) async {
    await tester.tap(find.byType(SessionCard).first);
    await tester.pumpAndSettle();
  }

  void expectOpenedPaymentLinkFor(AppUser user) {
    expect(urlOpener.opened, hasLength(1));
    final (:url, :windowName) = urlOpener.opened.single;
    expect(url.host, 'buy.stripe.com');
    expect(url.path, '/9AQ9BL9hpbkY4ZGeUV');
    expect(url.queryParameters['client_reference_id'], user.uid);
    expect(url.queryParameters['locked_prefilled_email'], user.email);
    expect(windowName, '_self');
  }

  setUp(() => urlOpener = FakeUrlOpener());

  testWidgets('signed in: opens the tagged payment link in the same tab', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    await tapFirstSession(tester);

    expect(find.byType(SignInDialog), findsNothing);
    expectOpenedPaymentLinkFor(testUser);
  });

  testWidgets('signed out: asks to sign in, then opens the payment link', (tester) async {
    const newUser = AppUser(uid: 'newUid', email: 'new@example.com');
    final auth = FakeAuthService()..nextSignIn = newUser;
    await pumpPage(tester, auth);

    await tapFirstSession(tester);
    expect(find.byType(SignInDialog), findsOneWidget);
    expect(urlOpener.opened, isEmpty);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expectOpenedPaymentLinkFor(newUser);
  });

  testWidgets('signed out: cancelling sign-in opens nothing', (tester) async {
    await pumpPage(tester, FakeAuthService());

    await tapFirstSession(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInDialog), findsNothing);
    expect(urlOpener.opened, isEmpty);
  });

  testWidgets('unknown package: does nothing, without asking to sign in', (tester) async {
    await pumpPage(tester, FakeAuthService(), packageName: '');

    await tapFirstSession(tester);

    expect(find.byType(SignInDialog), findsNothing);
    expect(urlOpener.opened, isEmpty);
  });
}
