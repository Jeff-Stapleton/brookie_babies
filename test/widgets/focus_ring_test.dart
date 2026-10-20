// requestFocusInView: keyboard focus scrolls the focused control well into
// view, so its focus ring is never cut off at the window's edge.

import 'package:brookie_babies/components/booking_calendar.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  /// [home] in the app as main.dart builds it: the traversal group from
  /// MaterialApp.builder around every page.
  Future<void> pumpApp(WidgetTester tester, Widget home, {Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppServices(
      auth: FakeAuthService(),
      bookings: FakeBookingService(),
      gallery: FakeGalleryService(),
      portfolio: FakePortfolioService(),
      admin: FakeAdminService(),
      openUrl: FakeUrlOpener().call,
      pickPhotos: FakePhotoPicker().call,
      isEmbeddedBrowser: false,
      child: MaterialApp(
        theme: brookieTheme(Brightness.light),
        builder: (context, child) => FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(requestFocusCallback: requestFocusInView),
          child: child!,
        ),
        home: home,
      ),
    ));
    await tester.pumpAndSettle();
  }

  bool hasFocus(WidgetTester tester, String label) => Focus.of(tester.element(find.text(label))).hasPrimaryFocus;

  Future<void> tabTo(WidgetTester tester, String label, {bool settle = true}) async {
    for (var i = 0; i < 8 && !hasFocus(tester, label); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }
    expect(hasFocus(tester, label), isTrue, reason: 'Tab should reach "$label"');
  }

  /// The page's own (vertical) scroll view.
  Finder pageScroller() =>
      find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down).first;
  ScrollPosition pagePosition(WidgetTester tester) => tester.state<ScrollableState>(pageScroller()).position;

  /// The focused control's ring, 4px outside it, sits at least [room] inside
  /// the page's scroll view.
  void expectRoomAround(WidgetTester tester, Finder control, {double room = BrookieSpace.s6}) {
    final view = tester.getRect(pageScroller());
    final ring = tester.getRect(control).inflate(4);
    expect(ring.top - view.top, greaterThanOrEqualTo(room - 4), reason: 'room above $ring in $view');
    expect(view.bottom - ring.bottom, greaterThanOrEqualTo(room - 4), reason: 'room below $ring in $view');
  }

  testWidgets('Tab to a package button scrolls it to the middle, with room for its ring', (tester) async {
    await pumpApp(tester, const HomePage());

    await tabTo(tester, 'Choose Basic');

    final button = find.widgetWithText(OutlinedButton, 'Choose Basic');
    expectRoomAround(tester, button);
    expect(tester.getCenter(button).dy, moreOrLessEquals(450, epsilon: 1));
    // The card's bottom edge shows too.
    expect(tester.getRect(find.ancestor(of: button, matching: find.byType(DecoratedBox)).first).bottom,
        lessThan(900));
  });

  testWidgets('it scrolls over the fade duration, easing out', (tester) async {
    await pumpApp(tester, const HomePage());
    await tabTo(tester, 'Book a session');
    final start = pagePosition(tester).pixels;

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(kBrookieFadeDuration ~/ 2);
    final halfway = pagePosition(tester).pixels;
    await tester.pumpAndSettle();
    final end = pagePosition(tester).pixels;

    expect(hasFocus(tester, 'Choose Basic'), isTrue);
    expect(halfway, greaterThan(start));
    // Ease-out covers more than half the way in the first half of the time.
    expect(halfway - start, greaterThan((end - start) / 2));
    expect(halfway, lessThan(end));
  });

  testWidgets('with reduced motion it jumps straight there', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, const HomePage());

    await tabTo(tester, 'Choose Basic', settle: false);

    // In place after one frame, and nothing left to scroll.
    expectRoomAround(tester, find.widgetWithText(OutlinedButton, 'Choose Basic'));
    final offset = pagePosition(tester).pixels;
    expect(pagePosition(tester).isScrollingNotifier.value, isFalse);
    await tester.pumpAndSettle();
    expect(pagePosition(tester).pixels, offset);
  });

  testWidgets('a control already comfortably in view leaves the page still', (tester) async {
    await pumpApp(tester, const HomePage());
    await tabTo(tester, 'Choose Basic');
    final offset = pagePosition(tester).pixels;

    // The next card's button sits beside it.
    await tabTo(tester, 'Choose Premium');

    expect(pagePosition(tester).pixels, offset);
  });

  for (final (name, size) in [('a phone', Size(390, 844)), ('a desktop', Size(1440, 900))]) {
    testWidgets('the calendar on $name: Tab still reads the days in order, and only the page scrolls',
        (tester) async {
      await pumpApp(
        tester,
        SchedulingPage(packageName: 'Premium', now: DateTime(2026, 10, 17, 8)),
        size: size,
      );
      final months = tester
          .state<ScrollableState>(find.descendant(of: find.byType(PageView), matching: find.byType(Scrollable)))
          .position;
      final month = months.pixels;

      Focus.of(tester.element(find.byIcon(Icons.chevron_right))).requestFocus();
      await tester.pumpAndSettle();
      final order = <String>[];
      for (var i = 0; i < 16; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final focused = FocusManager.instance.primaryFocus!.context!;
        final label = find.descendant(of: find.byElementPredicate((e) => e == focused), matching: find.byType(Text));
        order.add(tester.widget<Text>(label.first).data!);
        expect(months.pixels, month, reason: 'the month pages stay put at ${order.last}');
        final inCalendar = find.descendant(of: find.byType(BookingCalendar), matching: find.text(order.last));
        if (inCalendar.evaluate().isNotEmpty) expectRoomAround(tester, inCalendar);
      }

      expect(order, [for (var day = 17; day <= 31; day++) '$day', '9:00–9:30 am']);
    });
  }
}
