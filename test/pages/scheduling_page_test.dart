import 'package:brookie_babies/components/booking_calendar.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/widgets/session_slot.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Saturday, October 17, 2026, before the first session of the day.
final saturdayMorning = DateTime(2026, 10, 17, 8);

void main() {
  late FakeUrlOpener urlOpener;

  Future<void> pumpPage(
    WidgetTester tester,
    FakeAuthService auth, {
    String packageName = 'Premium',
    DateTime? now,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(testApp(
      auth: auth,
      urlOpener: urlOpener,
      home: SchedulingPage(packageName: packageName, now: now ?? saturdayMorning),
    ));
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // Scrolls the calendar into view as a whole: ensureVisible on a day would
  // also scroll the calendar's month pager.
  Future<void> tapDay(WidgetTester tester, String day) async {
    await tester.ensureVisible(find.byType(BookingCalendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text(day));
    await tester.pumpAndSettle();
  }

  Finder continueButton() => find.widgetWithText(FilledButton, 'Continue to payment');

  Future<void> chooseTimeAndContinue(WidgetTester tester) async {
    await tapVisible(tester, find.text('10:00–10:30 am'));
    await tapVisible(tester, continueButton());
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

  testWidgets('names the chosen package and opens on today with its times', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    expect(find.text('Book a session'), findsOneWidget);
    expect(find.text('Pick a session time'), findsOneWidget);
    expect(find.text('Premium session · \$50'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Saturday, October 17'), findsOneWidget);
    expect(find.byType(SessionSlot), findsNWidgets(5));
  });

  testWidgets('signed in: opens the tagged payment link in the same tab', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    await chooseTimeAndContinue(tester);

    expect(find.byType(SignInDialog), findsNothing);
    expectOpenedPaymentLinkFor(testUser);
  });

  testWidgets('signed out: asks to sign in, then opens the payment link', (tester) async {
    const newUser = AppUser(uid: 'newUid', email: 'new@example.com');
    final auth = FakeAuthService()..nextSignIn = newUser;
    await pumpPage(tester, auth);

    await chooseTimeAndContinue(tester);
    expect(find.byType(SignInDialog), findsOneWidget);
    expect(urlOpener.opened, isEmpty);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expectOpenedPaymentLinkFor(newUser);
  });

  testWidgets('signed out: cancelling sign-in opens nothing', (tester) async {
    await pumpPage(tester, FakeAuthService());

    await chooseTimeAndContinue(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInDialog), findsNothing);
    expect(urlOpener.opened, isEmpty);
  });

  testWidgets('unknown package: offers the packages, never sign-in or payment', (tester) async {
    final auth = FakeAuthService();
    await pumpPage(tester, auth, packageName: '');

    expect(find.byType(InlineMessage), findsOneWidget);
    expect(continueButton(), findsNothing);
    expect(find.byType(SessionSlot), findsNothing);
    expect(find.byType(SignInDialog), findsNothing);
    expect(auth.signInCalls, 0);
    expect(urlOpener.opened, isEmpty);
  });

  testWidgets('unknown package: "See packages" goes back to the first page', (tester) async {
    await tester.pumpWidget(testApp(
      auth: FakeAuthService(),
      urlOpener: urlOpener,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (context) => const SchedulingPage(packageName: ''),
          )),
          child: const Text('Packages'),
        ),
      ),
    ));
    await tester.tap(find.text('Packages'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a session time'), findsOneWidget);

    await tester.tap(find.text('See packages'));
    await tester.pumpAndSettle();

    expect(find.text('Pick a session time'), findsNothing);
    expect(find.text('Packages'), findsOneWidget);
  });

  testWidgets('continue is disabled until a time is chosen', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    expect(tester.widget<FilledButton>(continueButton()).onPressed, isNull);
    expect(find.text('Choose a time to continue.'), findsOneWidget);

    await tapVisible(tester, continueButton());
    expect(urlOpener.opened, isEmpty);

    await tapVisible(tester, find.text('1:00–1:30 pm'));

    expect(tester.widget<FilledButton>(continueButton()).onPressed, isNotNull);
    expect(find.text('Choose a time to continue.'), findsNothing);
    expect(find.text('Sat, Oct 17, 1:00–1:30 pm'), findsOneWidget);
  });

  testWidgets('past days can\'t be chosen; later days can', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    await tapDay(tester, '10');
    expect(find.text('Saturday, October 17'), findsOneWidget);
    expect(find.text('Saturday, October 10'), findsNothing);

    await tapDay(tester, '24');
    expect(find.text('Saturday, October 24'), findsOneWidget);
  });

  testWidgets('choosing another day clears the chosen time', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    await tapVisible(tester, find.text('9:00–9:30 am'));
    expect(tester.widget<FilledButton>(continueButton()).onPressed, isNotNull);

    await tapDay(tester, '20');

    expect(find.text('Tuesday, October 20'), findsOneWidget);
    expect(tester.widget<FilledButton>(continueButton()).onPressed, isNull);
  });

  testWidgets('today offers only the times still ahead', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser), now: DateTime(2026, 10, 17, 10, 30));

    expect(find.text('Saturday, October 17'), findsOneWidget);
    expect(find.text('9:00–9:30 am'), findsNothing);
    expect(find.text('10:00–10:30 am'), findsNothing);
    expect(find.text('11:00–11:30 am'), findsOneWidget);
  });

  testWidgets('after the last time today, opens on tomorrow', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser), now: DateTime(2026, 10, 17, 15));

    expect(find.text('Sunday, October 18'), findsOneWidget);
    expect(find.byType(SessionSlot), findsNWidgets(5));

    // Today is over, so it can't be chosen either.
    await tapDay(tester, '17');
    expect(find.text('Sunday, October 18'), findsOneWidget);
  });

  testWidgets('session times read like the site writes them', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    for (final label in ['9:00–9:30 am', '10:00–10:30 am', '11:00–11:30 am', '1:00–1:30 pm', '2:00–2:30 pm']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining(' - '), findsNothing);
    expect(find.textContaining('AM'), findsNothing);
    expect(find.textContaining('PM'), findsNothing);
  });

  testWidgets('shows no street address or internal notes', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    expect(find.textContaining('Wild Rice'), findsNothing);
    expect(find.textContaining('10652'), findsNothing);
    expect(find.textContaining('Testing'), findsNothing);
    expect(find.text(SessionSlot.locationNote), findsNWidgets(5));
  });

  testWidgets('steps through months within the booking window', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    final previous = find.byTooltip('Previous month');
    final next = find.byTooltip('Next month');
    IconButton button(Finder finder) =>
        tester.widget<IconButton>(find.ancestor(of: finder, matching: find.byType(IconButton)));

    expect(button(previous).onPressed, isNull);

    for (final month in ['November 2026', 'December 2026', 'January 2027']) {
      await tapVisible(tester, next);
      expect(find.text(month), findsOneWidget);
    }
    // The window ends about three months out.
    expect(button(next).onPressed, isNull);

    await tapVisible(tester, previous);
    expect(find.text('December 2026'), findsOneWidget);
  });

  testWidgets('exposes the chosen day and time to assistive technology', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));
    await tapVisible(tester, find.text('11:00–11:30 am'));

    expect(
      tester.getSemantics(find.text('11:00–11:30 am')),
      isSemantics(isInMutuallyExclusiveGroup: true, isChecked: true, hasCheckedState: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.text('9:00–9:30 am')),
      isSemantics(isInMutuallyExclusiveGroup: true, isChecked: false, hasCheckedState: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.text('17')),
      isSemantics(label: 'Saturday, October 17, 2026', isButton: true, isSelected: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.text('16')),
      isSemantics(label: 'Friday, October 16, 2026', isButton: true, isSelected: false, hasEnabledState: true),
    );
    semantics.dispose();
  });

  for (final (name, size) in [('phone', Size(360, 740)), ('desktop', Size(1440, 900))]) {
    testWidgets('lays out without overflow on a $name', (tester) async {
      await pumpPage(tester, FakeAuthService(signedInAs: testUser), size: size);
      await tapVisible(tester, find.text('10:00–10:30 am'));

      expect(tester.takeException(), isNull);
      final calendar = tester.getRect(find.text('October 2026'));
      final times = tester.getRect(find.text('Saturday, October 17'));
      if (size.width >= 900) {
        expect(times.left, greaterThan(calendar.right), reason: 'times sit beside the calendar');
      } else {
        expect(times.top, greaterThan(calendar.bottom), reason: 'times sit under the calendar');
      }
    });
  }
}
