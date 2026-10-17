import 'package:brookie_babies/components/booking_calendar.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/empty_state.dart';
import 'package:brookie_babies/widgets/session_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

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

  /// The 44px disc of [day] in the month on show.
  Finder disc(String day) => find
      .ancestor(
        of: find.descendant(of: find.byType(BookingCalendar), matching: find.text(day)),
        matching: find.byType(AnimatedContainer),
      )
      .first;

  Finder openingsDot(String day) =>
      find.descendant(of: disc(day), matching: find.byWidgetPredicate((w) => '${w.runtimeType}' == '_OpeningsDot'));

  /// The first line of text inside the control that has keyboard focus.
  String? focusedLabel(WidgetTester tester) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return null;
    final texts = find.descendant(of: find.byElementPredicate((e) => e == focused), matching: find.byType(Text));
    return texts.evaluate().isEmpty ? null : tester.widget<Text>(texts.first).data;
  }

  FocusNode monthButton(WidgetTester tester, IconData chevron) => Focus.of(tester.element(find.byIcon(chevron)));

  void expectFullSize(Rect disc, String day) {
    expect(disc.width, moreOrLessEquals(BrookieSize.day, epsilon: 0.01), reason: day);
    expect(disc.height, moreOrLessEquals(BrookieSize.day, epsilon: 0.01), reason: day);
  }

  final octoberDays = [for (var day = 1; day <= 31; day++) '$day'];

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

    final band = find.byType(EmptyState);
    expect(band, findsOneWidget);
    expect(find.descendant(of: band, matching: find.text('Choose a package first, then pick a time for your session.')),
        findsOneWidget);
    expect(find.descendant(of: band, matching: find.widgetWithText(OutlinedButton, 'See packages')), findsOneWidget);
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

  testWidgets('unknown package: "See packages" goes home and scrolls to the packages', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(auth: FakeAuthService(), urlOpener: urlOpener, home: const HomePage()));
    await tester.pumpAndSettle();
    expect(find.text('Choose your package').hitTestable(), findsNothing);

    Navigator.of(tester.element(find.byType(HomePage))).push(MaterialPageRoute<void>(
      builder: (context) => const SchedulingPage(packageName: ''),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See packages'));
    await tester.pumpAndSettle();

    expect(find.byType(SchedulingPage), findsNothing);
    expect(find.text('Choose your package').hitTestable(), findsOneWidget);
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

  testWidgets('a time chosen in next year names the year', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    for (var i = 0; i < 3; i++) {
      await tapVisible(tester, find.byTooltip('Next month'));
    }
    await tapDay(tester, '15');
    await tapVisible(tester, find.text('9:00–9:30 am'));

    expect(find.text('Friday, January 15'), findsOneWidget);
    expect(find.text('Fri, Jan 15, 2027, 9:00–9:30 am'), findsOneWidget);
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
      isSemantics(
        label: 'Friday, October 16, 2026',
        isButton: true,
        isSelected: false,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('days with openings carry a dot, explained under the calendar', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    expect(find.text('Openings that day'), findsOneWidget);
    // Past days have no openings.
    for (final day in ['1', '10', '16']) {
      expect(openingsDot(day), findsNothing, reason: day);
    }
    for (final day in ['17', '18', '24', '31']) {
      expect(openingsDot(day), findsOneWidget, reason: day);
    }
    // On the chosen day the dot is on-butter, like its numeral.
    final c = BrookieColors.light;
    Color dotColor(String day) => (tester
            .widget<DecoratedBox>(find.descendant(of: openingsDot(day), matching: find.byType(DecoratedBox)))
            .decoration as BoxDecoration)
        .color!;
    expect(dotColor('17'), c.onButter);
    expect(dotColor('18'), c.ink);
  });

  testWidgets('keyboard: the month buttons hand focus to each other at the window\'s edges', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser), size: const Size(1440, 900));

    monthButton(tester, Icons.chevron_right).requestFocus();
    await tester.pump();
    for (final month in ['November 2026', 'December 2026', 'January 2027']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text(month), findsOneWidget);
    }
    // Next month switched off; focus moved to Previous month, not the top bar.
    expect(FocusManager.instance.primaryFocus, monthButton(tester, Icons.chevron_left));

    for (final month in ['December 2026', 'November 2026', 'October 2026']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text(month), findsOneWidget);
    }
    expect(FocusManager.instance.primaryFocus, monthButton(tester, Icons.chevron_right));
  });

  for (final (name, size) in [('a phone', Size(390, 844)), ('a desktop', Size(1440, 900))]) {
    testWidgets('keyboard: the arrow keys move day to day and never slide the month, on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Flutter's bindings on the web, where the arrow keys scroll the
      // nearest scroll view: here, the calendar's month pages.
      await tester.pumpWidget(testApp(
        auth: FakeAuthService(signedInAs: testUser),
        urlOpener: urlOpener,
        home: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowUp): ScrollIntent(direction: AxisDirection.up),
            SingleActivator(LogicalKeyboardKey.arrowDown): ScrollIntent(direction: AxisDirection.down),
            SingleActivator(LogicalKeyboardKey.arrowLeft): ScrollIntent(direction: AxisDirection.left),
            SingleActivator(LogicalKeyboardKey.arrowRight): ScrollIntent(direction: AxisDirection.right),
          },
          child: SchedulingPage(packageName: 'Premium', now: saturdayMorning),
        ),
      ));
      await tester.ensureVisible(find.byType(BookingCalendar));
      await tester.pumpAndSettle();
      final months = tester
          .state<ScrollableState>(find.descendant(of: find.byType(PageView), matching: find.byType(Scrollable)))
          .position;
      final month = months.pixels;
      Focus.of(tester.element(find.descendant(of: find.byType(BookingCalendar), matching: find.text('20'))))
          .requestFocus();
      await tester.pump();

      for (final (key, day) in [
        (LogicalKeyboardKey.arrowRight, '21'),
        (LogicalKeyboardKey.arrowDown, '28'),
        (LogicalKeyboardKey.arrowLeft, '27'),
        (LogicalKeyboardKey.arrowUp, '20'),
        (LogicalKeyboardKey.arrowLeft, '19'),
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(months.pixels, month, reason: '$key mid-way');
        await tester.pumpAndSettle();
        expect(focusedLabel(tester), day, reason: '$key');
        expect(months.pixels, month, reason: '$key');
        expect(find.text('October 2026'), findsOneWidget);
      }
    });

    testWidgets('keyboard: Tab reads the days in order, then the times, on $name', (tester) async {
      await pumpPage(tester, FakeAuthService(signedInAs: testUser), size: size);

      monthButton(tester, Icons.chevron_right).requestFocus();
      await tester.pump();
      final order = <String?>[];
      for (var i = 0; i < 16; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        order.add(focusedLabel(tester));
      }

      expect(order, [for (var day = 17; day <= 31; day++) '$day', '9:00–9:30 am']);
    });
  }

  // The month pages clip at their edges: a day's 1.5px selection ring and its
  // focus ring (4px out) must fit inside them on the outer columns and the
  // last week.
  for (final (name, size) in [
    ('320', Size(320, 568)),
    ('360', Size(360, 740)),
    ('375', Size(375, 667)),
    ('390', Size(390, 844)),
    ('768', Size(768, 1024)),
    ('1440', Size(1440, 900)),
  ]) {
    testWidgets('$name wide: full-size days with room for their rings', (tester) async {
      await pumpPage(tester, FakeAuthService(signedInAs: testUser), size: size);
      await tester.ensureVisible(find.byType(BookingCalendar));
      await tester.pumpAndSettle();

      final page = tester.getRect(find.descendant(of: find.byType(BookingCalendar), matching: find.byType(PageView)));
      for (final day in octoberDays) {
        final rect = tester.getRect(disc(day));
        expectFullSize(rect, day);
        final ring = rect.inflate(4);
        expect(
          ring.left >= page.left && ring.right <= page.right && ring.bottom <= page.bottom,
          isTrue,
          reason: 'ring around $day ($ring) inside the month page ($page)',
        );
      }
    });
  }

  testWidgets('narrowest phones: the calendar runs edge to edge to keep full-size days', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser), size: const Size(320, 568));

    expect(tester.getRect(find.byType(BookingCalendar)).width, 320);
    // The times stay inside the page gutter.
    expect(tester.getRect(find.byType(SessionSlot).first).left, BrookieSpace.s4);
  });

  for (final width in [600.0, 768.0, 899.0]) {
    testWidgets('stacked at ${width.round()}px: the times end with the calendar; the button fits its label',
        (tester) async {
      await pumpPage(tester, FakeAuthService(signedInAs: testUser), size: Size(width, 1024));

      final slot = tester.getRect(find.byType(SessionSlot).first);
      final calendar = tester.getRect(find.byType(BookingCalendar));
      expect(slot.top, greaterThan(calendar.bottom));
      expect(calendar.width, BookingCalendar.maxWidth);
      expect(slot.left, calendar.left);
      expect(slot.right, calendar.right);
      expect(tester.getSize(continueButton()).width, lessThan(slot.width));
    });
  }

  testWidgets('side by side, the times keep their own width', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser), size: const Size(1440, 900));

    expect(tester.getSize(find.byType(SessionSlot).first).width, 520);
  });

  testWidgets('on a phone the button fills the column', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser));

    expect(tester.getSize(continueButton()).width, tester.getSize(find.byType(SessionSlot).first).width);
  });

  testWidgets('at 200% text on the narrowest phone, numerals shrink to fit above the dot', (tester) async {
    await pumpPage(tester, FakeAuthService(signedInAs: testUser), size: const Size(320, 568), textScale: 2);
    await tester.ensureVisible(find.byType(BookingCalendar));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final day in octoberDays) {
      final box = tester.getRect(disc(day));
      final text = tester.getRect(find.descendant(of: disc(day), matching: find.text(day)));
      expectFullSize(box, day);
      // One line, inside the disc, and no taller than 1.5 times the label's
      // 20px line, so the figures stay clear of the dot.
      expect(text.width, lessThanOrEqualTo(BrookieSize.day - 8 + 0.01), reason: day);
      expect(text.height, lessThanOrEqualTo(30.01), reason: day);
      expect(text.center.dx, moreOrLessEquals(box.center.dx, epsilon: 0.01), reason: day);
      expect(text.center.dy, moreOrLessEquals(box.center.dy, epsilon: 0.01), reason: day);
    }
    for (final day in ['18', '31']) {
      final dot = tester.getRect(openingsDot(day));
      expect(dot.bottom, moreOrLessEquals(tester.getRect(disc(day)).bottom - 6, epsilon: 0.01), reason: day);
    }
  });

  for (final (name, size, scale) in [
    ('a 320 phone', Size(320, 568), 1.0),
    ('a 360 phone', Size(360, 740), 1.0),
    ('a tablet', Size(768, 1024), 1.0),
    ('a desktop', Size(1440, 900), 1.0),
    ('a 360 phone at 200% text', Size(360, 740), 2.0),
    ('a 390 phone at 200% text', Size(390, 844), 2.0),
    ('a desktop at 200% text', Size(1440, 900), 2.0),
  ]) {
    testWidgets('lays out without overflow on $name', (tester) async {
      await pumpPage(tester, FakeAuthService(signedInAs: testUser), size: size, textScale: scale);
      await tapVisible(tester, find.text('10:00–10:30 am'));

      expect(tester.takeException(), isNull);
      final calendar = tester.getRect(find.byType(BookingCalendar));
      final times = tester.getRect(find.text('Saturday, October 17'));
      if (size.width >= 900) {
        expect(times.left, greaterThan(calendar.right), reason: 'times sit beside the calendar');
      } else {
        expect(times.top, greaterThan(calendar.bottom), reason: 'times sit under the calendar');
      }
    });
  }
}
