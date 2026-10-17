import 'package:brookie_babies/components/account_button.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Widget app(FakeAuthService auth, {bool onPhoto = false, bool showSessionsLink = true}) => testApp(
        auth: auth,
        home: Scaffold(
          body: Center(child: AccountButton(onPhoto: onPhoto, showSessionsLink: showSessionsLink)),
        ),
      );

  /// The chip's painted surface: its fill and its edge.
  final chipFinder = find.descendant(of: find.byType(OutlinedButton), matching: find.byType(Material));
  Material chipSurface(WidgetTester tester) => tester.widget<Material>(chipFinder);

  /// The avatar button's painted surface.
  final avatarFinder = find.descendant(of: find.byType(IconButton), matching: find.byType(Material));
  BorderSide avatarSide(WidgetTester tester) =>
      (tester.widget<Material>(avatarFinder).shape! as OutlinedBorder).side;

  /// The painted surface of the menu item labelled [label].
  BorderSide itemSide(WidgetTester tester, String label) => (tester
          .widget<Material>(find.descendant(of: find.widgetWithText(MenuItemButton, label), matching: find.byType(Material)))
          .shape! as OutlinedBorder)
      .side;

  bool hasFocus(WidgetTester tester, Finder finder) => Focus.of(tester.element(finder)).hasPrimaryFocus;

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  final focusRing = brookieFocusSide(BrookieColors.light.focus);

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

  testWidgets('the chip label is 15px, a size down from a button', (tester) async {
    await tester.pumpWidget(app(FakeAuthService()));

    final label = tester.renderObject<RenderParagraph>(find.text('Sign in'));
    expect(label.text.style!.fontSize, 15);
    expect(label.text.style!.fontWeight, FontWeight.w500);
  });

  testWidgets('signed out on paper: keyboard focus draws the gap ring', (tester) async {
    await tester.pumpWidget(app(FakeAuthService()));
    await key(tester, LogicalKeyboardKey.tab);

    expect((chipSurface(tester).shape! as OutlinedBorder).side, focusRing);
    expect(find.byType(FocusRing), findsNothing);
  });

  testWidgets('signed out on a photograph: keyboard focus draws the two-tone ring', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(), onPhoto: true));
    expect(tester.widget<FocusRing>(find.byType(FocusRing)).visible, isFalse);

    await key(tester, LogicalKeyboardKey.tab);

    expect(tester.widget<FocusRing>(find.byType(FocusRing)).visible, isTrue);
    // The ink ring alone vanishes into a dark print, so it isn't drawn.
    expect((chipSurface(tester).shape! as OutlinedBorder).side, BorderSide.none);
    // The ring paints outside the chip, so the chip mustn't clip it.
    expect(chipSurface(tester).clipBehavior, Clip.none);
  });

  testWidgets('signed in on paper: keyboard focus rings the avatar with a gap', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser)));
    expect(avatarSide(tester), BorderSide.none);

    await key(tester, LogicalKeyboardKey.tab);

    expect(avatarSide(tester), focusRing);
    expect(find.byType(FocusRing), findsNothing);
  });

  testWidgets('signed in on a photograph: the avatar gets the two-tone ring', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser), onPhoto: true));
    expect(tester.widget<FocusRing>(find.byType(FocusRing)).visible, isFalse);

    await key(tester, LogicalKeyboardKey.tab);

    expect(tester.widget<FocusRing>(find.byType(FocusRing)).visible, isTrue);
    expect(avatarSide(tester), BorderSide.none);
  });

  testWidgets('the menu has a hairline edge and casts no shadow', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser)));
    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();

    final panel = tester.widget<Material>(
      find.ancestor(of: find.text('Pat Parent'), matching: find.byType(Material)).first,
    );
    expect(panel.elevation, 0);
    expect(panel.color, BrookieColors.light.surface);
    expect((panel.shape! as RoundedRectangleBorder).side.color, BrookieColors.light.line);
  });

  testWidgets('the menu hangs from the avatar, right edges lined up', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser)));
    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();

    final avatar = tester.getRect(find.byType(CircleAvatar));
    final panel = tester.getRect(find.ancestor(of: find.text('Pat Parent'), matching: find.byType(Material)).first);
    expect(panel.right, moreOrLessEquals(avatar.right));
    expect(panel.top, moreOrLessEquals(avatar.bottom + BrookieSpace.s2));
  });

  testWidgets('a click opens the menu without moving focus into it', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser)));
    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();

    expect(hasFocus(tester, find.text('Your sessions')), isFalse);
    expect(hasFocus(tester, find.text('Sign out')), isFalse);
    expect(itemSide(tester, 'Your sessions'), BorderSide.none);
  });

  testWidgets('keyboard: Enter opens on the first item, arrows wrap, Home and End jump, Escape returns',
      (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser)));
    await key(tester, LogicalKeyboardKey.tab);
    expect(hasFocus(tester, find.byType(CircleAvatar)), isTrue);

    await key(tester, LogicalKeyboardKey.enter);
    expect(hasFocus(tester, find.text('Your sessions')), isTrue);
    // A real ring, not just a tint.
    expect(itemSide(tester, 'Your sessions'), focusRing);
    expect(itemSide(tester, 'Sign out'), BorderSide.none);

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(hasFocus(tester, find.text('Sign out')), isTrue);
    expect(itemSide(tester, 'Sign out'), focusRing);

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(hasFocus(tester, find.text('Your sessions')), isTrue);

    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(hasFocus(tester, find.text('Sign out')), isTrue);

    await key(tester, LogicalKeyboardKey.home);
    expect(hasFocus(tester, find.text('Your sessions')), isTrue);

    await key(tester, LogicalKeyboardKey.end);
    expect(hasFocus(tester, find.text('Sign out')), isTrue);

    await key(tester, LogicalKeyboardKey.escape);
    expect(find.text('Sign out'), findsNothing);
    expect(hasFocus(tester, find.byType(CircleAvatar)), isTrue);
  });

  testWidgets('keyboard: the up arrow opens the menu on its last item', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser)));
    await key(tester, LogicalKeyboardKey.tab);

    await key(tester, LogicalKeyboardKey.arrowUp);

    expect(hasFocus(tester, find.text('Sign out')), isTrue);
  });

  testWidgets('keyboard: Enter on "Sign out" signs out', (tester) async {
    final auth = FakeAuthService(signedInAs: testUser);
    await tester.pumpWidget(app(auth));
    await key(tester, LogicalKeyboardKey.tab);
    await key(tester, LogicalKeyboardKey.enter);
    await key(tester, LogicalKeyboardKey.end);

    await key(tester, LogicalKeyboardKey.enter);

    expect(auth.currentUser, isNull);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the avatar says whether its menu is open', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser)));

    expect(tester.getSemantics(find.byTooltip('Account')),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: false));
    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byTooltip('Account')),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: true));
    semantics.dispose();
  });

  testWidgets('on "Your sessions" itself, the menu leaves out the link', (tester) async {
    await tester.pumpWidget(app(FakeAuthService(signedInAs: testUser), showSessionsLink: false));
    await key(tester, LogicalKeyboardKey.tab);
    await key(tester, LogicalKeyboardKey.enter);

    expect(find.text('Your sessions'), findsNothing);
    expect(find.byType(MenuItemButton), findsOneWidget);
    expect(hasFocus(tester, find.text('Sign out')), isTrue);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(hasFocus(tester, find.text('Sign out')), isTrue);
  });

  testWidgets('a long email fits a narrow phone and the menu stays inside the gutters', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const user = AppUser(
      uid: 'u3',
      email: 'a.very.long.address.for.a.family@example.com',
      displayName: 'Alexandra Montgomery-Fitzwilliam',
    );
    await tester.pumpWidget(testApp(
      auth: FakeAuthService(signedInAs: user),
      home: const Scaffold(body: Align(alignment: Alignment.topRight, child: AccountButton())),
    ));
    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final panel = tester.getRect(find.ancestor(of: find.text(user.email!), matching: find.byType(Material)).first);
    expect(panel.left, greaterThanOrEqualTo(BrookieSpace.s4));
  });
}
