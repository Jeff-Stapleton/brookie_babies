import 'package:brookie_babies/components/account_button.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Widget app(FakeAuthService auth, {bool onPhoto = false}) => testApp(
        auth: auth,
        home: Scaffold(body: Center(child: AccountButton(onPhoto: onPhoto))),
      );

  /// The chip's painted surface: its fill and its edge.
  final chipFinder = find.descendant(of: find.byType(OutlinedButton), matching: find.byType(Material));
  Material chipSurface(WidgetTester tester) => tester.widget<Material>(chipFinder);

  testWidgets('signed out: "Sign in" opens the sign-in dialog', (tester) async {
    await tester.pumpWidget(app(FakeAuthService()));

    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInDialog), findsOneWidget);
  });

  testWidgets('signed out on paper: a surface chip with a strong edge', (tester) async {
    await tester.pumpWidget(app(FakeAuthService()));

    final chip = chipSurface(tester);
    expect(chip.color, BrookieColors.light.surface);
    final side = (chip.shape! as OutlinedBorder).side;
    expect(side.color, BrookieColors.light.lineStrong);
    expect(side.width, 1.5);
    expect(tester.getSize(chipFinder).height, BrookieSize.controlSm);
  });

  testWidgets('signed out on a photograph: a paper chip with no edge', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(), onPhoto: true));

    final chip = chipSurface(tester);
    expect(chip.color, BrookieColors.light.paper);
    expect((chip.shape! as OutlinedBorder).side, BorderSide.none);
  });

  testWidgets('signed in: shows the account menu and signs out', (tester) async {
    final auth = FakeAuthService(signedInAs: testUser);
    await tester.pumpWidget(app(auth));

    expect(find.text('Sign in'), findsNothing);
    expect(find.text('P'), findsOneWidget);
    expect(find.byTooltip('Account'), findsOneWidget);

    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
    expect(find.text('Pat Parent'), findsOneWidget);
    expect(find.text('parent@example.com'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(auth.currentUser, isNull);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('signed in: the avatar is a butter disc', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser)));

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundColor, BrookieColors.light.butter);
    expect(tester.getSize(find.byType(CircleAvatar)), const Size.square(BrookieSize.controlSm));
  });

  testWidgets('the menu header shows just the email when there is no name', (tester) async {
    const user = AppUser(uid: 'u2', email: 'family@example.com');
    await tester.pumpWidget(app(FakeAuthService(signedInAs: user)));

    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();

    expect(find.text('family@example.com'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
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

  testWidgets('signed in: "Your sessions" opens the profile page', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser)));

    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Your sessions'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfilePage), findsOneWidget);
  });
}
