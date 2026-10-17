import 'package:brookie_babies/components/session_list.dart';
import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/widgets/session_slot.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  final chosen = <SessionTime>[];

  Future<void> pumpList(WidgetTester tester, {SessionTime? selected, Set<SessionTime> taken = const {}}) async {
    await tester.pumpWidget(testApp(
      auth: FakeAuthService(),
      home: Scaffold(
        body: SessionList(
          day: DateTime(2026, 10, 24),
          times: SessionTime.all,
          selected: selected,
          taken: taken,
          onSelected: chosen.add,
        ),
      ),
    ));
  }

  setUp(chosen.clear);

  testWidgets('heads the times with the day and offers each one', (tester) async {
    await pumpList(tester);

    expect(find.text('Saturday, October 24'), findsOneWidget);
    expect(find.byType(SessionSlot), findsNWidgets(SessionTime.all.length));
    expect(find.byType(StatusTag), findsNothing);
  });

  testWidgets('choosing a slot reports its time', (tester) async {
    await pumpList(tester);

    await tester.tap(find.text('1:00–1:30 pm'));

    expect(chosen, [const SessionTime(13)]);
  });

  testWidgets('a taken slot says so and can\'t be chosen', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpList(tester, taken: {const SessionTime(10)});

    final slot = find.widgetWithText(SessionSlot, '10:00–10:30 am');
    expect(find.descendant(of: slot, matching: find.widgetWithText(StatusTag, 'Taken')), findsOneWidget);

    await tester.tap(find.text('10:00–10:30 am'));
    expect(chosen, isEmpty);
    expect(
      tester.getSemantics(find.text('10:00–10:30 am')),
      isSemantics(isInMutuallyExclusiveGroup: true, hasEnabledState: true, isEnabled: false),
    );
    semantics.dispose();
  });

  testWidgets('arrow keys move the choice between open slots', (tester) async {
    await pumpList(tester, selected: const SessionTime(9), taken: {const SessionTime(10)});

    // Tab lands on the chosen slot; the arrow skips the taken one.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(chosen, [const SessionTime(11)]);
  });
}
