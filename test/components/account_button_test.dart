import 'package:brookie_babies/components/account_button.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Widget app(FakeAuthService auth) => testApp(
        auth: auth,
        home: const Scaffold(body: Center(child: AccountButton())),
      );

  testWidgets('signed out: "Sign in" opens the sign-in dialog', (tester) async {
    await tester.pumpWidget(app(FakeAuthService()));

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInDialog), findsOneWidget);
  });

  testWidgets('signed in: shows the account menu and signs out', (tester) async {
    final auth = FakeAuthService(signedInAs: testUser);
    await tester.pumpWidget(app(auth));

    expect(find.text('Sign in'), findsNothing);
    expect(find.text('P'), findsOneWidget);

    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
    expect(find.text('parent@example.com'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(auth.currentUser, isNull);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('switches to the avatar when the user signs in', (tester) async {
    final auth = FakeAuthService()..nextSignIn = testUser;
    await tester.pumpWidget(app(auth));

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInDialog), findsNothing);
    expect(find.text('P'), findsOneWidget);
  });

  testWidgets('signed in: "My sessions" opens the profile page', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser)));

    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My sessions'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfilePage), findsOneWidget);
  });
}
