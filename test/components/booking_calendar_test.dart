// BookingCalendar's showOpenings flag. Choosing days by tap and keyboard,
// and the layout at many widths, are tested through the booking page
// (test/pages/scheduling_page_test.dart).

import 'package:brookie_babies/components/booking_calendar.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCalendar(WidgetTester tester, {bool? showOpenings}) async {
    final today = DateTime(2026, 10, 19);
    final calendar = showOpenings == null
        ? BookingCalendar(
            firstDay: today,
            lastDay: DateTime(2027, 1, 19),
            today: today,
            selectedDay: today,
            onDaySelected: (day) {},
          )
        : BookingCalendar(
            firstDay: DateTime(2020),
            lastDay: DateTime(2027, 10, 19),
            today: today,
            selectedDay: today,
            onDaySelected: (day) {},
            showOpenings: showOpenings,
          );
    await tester.pumpWidget(MaterialApp(
      theme: brookieTheme(Brightness.light),
      home: Scaffold(body: Center(child: SizedBox(width: BookingCalendar.maxWidth, child: calendar))),
    ));
  }

  /// The 4px dots under days with openings.
  Finder dots() => find.byWidgetPredicate((widget) => '${widget.runtimeType}' == '_OpeningsDot');

  testWidgets('by default, dots the days with openings and explains the dot', (tester) async {
    await pumpCalendar(tester);

    expect(tester.widget<BookingCalendar>(find.byType(BookingCalendar)).showOpenings, isTrue);
    expect(find.text('Openings that day'), findsOneWidget);
    // Today through the end of October, and the legend's own.
    expect(dots(), findsNWidgets(13 + 1));
  });

  testWidgets('without openings: no dots and no legend, and every day in range can still be chosen',
      (tester) async {
    await pumpCalendar(tester, showOpenings: false);

    expect(find.text('Openings that day'), findsNothing);
    expect(dots(), findsNothing);
    expect(tester.takeException(), isNull);

    // A past day in the range, ink like any other choosable day.
    final day = tester.widget<Text>(find.text('5'));
    expect(day.style!.color, BrookieColors.light.ink);
  });
}
