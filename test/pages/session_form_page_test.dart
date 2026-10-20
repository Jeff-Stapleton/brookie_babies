// SessionFormPage: adding an ad hoc session and editing one, the fields and
// what they accept, the date dialog, and saving.

import 'package:brookie_babies/components/booking_calendar.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/pages/admin_session_page.dart';
import 'package:brookie_babies/pages/session_form_page.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/brookie_dialog.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/admin_test_app.dart';
import '../support/fakes.dart';

/// The text field labelled [label].
Finder _field(String label) => find.widgetWithText(TextFormField, label);

/// The date field (it opens the calendar).
Finder _dateField() => find.ancestor(of: find.text('Date'), matching: find.byType(InputDecorator));

/// [label] inside the open dialog.
Finder _inDialog(String label) => find.descendant(of: find.byType(BrookieDialog), matching: find.text(label));

/// Opens the dropdown showing [current] and chooses [label] in it.
Future<void> _choose(WidgetTester tester, String current, String label) async {
  await tapInView(tester, find.text(current));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Opens the calendar and chooses day [day] of the month it shows.
Future<void> _chooseDay(WidgetTester tester, int day) async {
  await tapInView(tester, _dateField());
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(BookingCalendar), matching: find.text('$day')));
  await tester.pumpAndSettle();
  await tester.tap(_inDialog('Use this date'));
  await tester.pumpAndSettle();
}

/// Fills in the required fields, with spaces and capitals to tidy away.
Future<void> _fillIn(WidgetTester tester) async {
  await tester.enterText(_field('Name'), '  The Novak family ');
  await tester.enterText(_field('Email'), ' Novak@Example.com');
  await _chooseDay(tester, 15);
}

/// [SessionFormPage] over a page to come back to.
Future<NavigatorState> _pumpOver(WidgetTester tester, FakeAdminService admin, SessionFormPage form) async {
  await pumpAdminPage(tester, const Scaffold(body: Text('Below')), admin: admin, size: const Size(1440, 1200));
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(MaterialPageRoute<void>(builder: (context) => form));
  await tester.pumpAndSettle();
  return navigator;
}

void main() {
  final now = DateTime.now();

  group('adding', () {
    testWidgets('the fields, what each is for, and the one primary button', (tester) async {
      await pumpAdminPage(tester, const SessionFormPage(), size: const Size(1440, 1200));

      expect(find.text('Add a session'), findsNWidgets(2));
      expect(find.text('For family, friends and anyone not booked on the site. No payment needed.'), findsOneWidget);
      expect(find.text('Who it’s for, such as “The Harper family”.'), findsOneWidget);
      expect(find.text('The email they use to sign in to Google.'), findsOneWidget);
      expect(find.text('No package'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('No time'), findsOneWidget);
      expect(find.text('Location (optional)'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add session'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(filledButtons(), 1);
    });

    testWidgets('typed text is set in Jost, like the site’s other controls', (tester) async {
      await pumpAdminPage(tester, const SessionFormPage());

      final style =
          tester.widget<EditableText>(find.descendant(of: _field('Name'), matching: find.byType(EditableText))).style;
      expect(style.fontFamily, BrookieType.ui.fontFamily);
      expect(style.fontSize, BrookieType.ui.fontSize);
    });

    testWidgets('packages: none, or one of the three', (tester) async {
      await pumpAdminPage(tester, const SessionFormPage(), size: const Size(1440, 1200));

      await tapInView(tester, find.text('No package'));
      await tester.pumpAndSettle();
      for (final label in ['No package', 'Basic', 'Premium', 'Ultimate']) {
        expect(find.text(label).hitTestable(), findsWidgets);
      }
    });

    testWidgets('times: none, or every quarter hour from 6:00 am to 9:00 pm', (tester) async {
      await pumpAdminPage(tester, const SessionFormPage(), size: const Size(1440, 1200));

      final dropdown = tester.widget<DropdownButton<({int hour, int minute})?>>(
          find.byType(DropdownButton<({int hour, int minute})?>));
      final labels = [for (final item in dropdown.items!) (item.child as Text).data];
      expect(labels.first, 'No time');
      expect(labels[1], '6:00 am');
      expect(labels[2], '6:15 am');
      expect(labels.last, '9:00 pm');
      expect(labels, hasLength(1 + 15 * 4 + 1));
      expect(labels, contains('12:00 pm'));
    });

    testWidgets('empty: says what each required field needs, and focuses the first', (tester) async {
      final admin = FakeAdminService();
      await pumpAdminPage(tester, const SessionFormPage(), admin: admin, size: const Size(1440, 1200));

      await tester.tap(find.text('Add session'));
      await tester.pumpAndSettle();

      expect(find.text('Enter who the session is for.'), findsOneWidget);
      expect(find.text('Enter the email they use to sign in to Google.'), findsOneWidget);
      expect(find.text('Choose the day of the session.'), findsOneWidget);
      expect(admin.calls, isEmpty);
      expect(tester.widget<EditableText>(find.descendant(of: _field('Name'), matching: find.byType(EditableText)))
          .focusNode.hasFocus, isTrue);
    });

    testWidgets('checks each field against what the rules accept, and clears as it’s fixed', (tester) async {
      await pumpAdminPage(tester, const SessionFormPage(), size: const Size(1440, 1200));

      await tester.enterText(_field('Name'), 'x' * 101);
      await tester.enterText(_field('Email'), 'harper@example');
      await tester.enterText(_field('Location (optional)'), 'y' * 201);
      await tester.tap(find.text('Add session'));
      await tester.pumpAndSettle();

      expect(find.text('Shorten the name to 100 characters or fewer.'), findsOneWidget);
      expect(find.text('That isn’t a whole email address. Check it, like name@gmail.com.'), findsOneWidget);
      expect(find.text('Shorten the location to 200 characters or fewer.'), findsOneWidget);

      // Checked as they change from now on.
      await tester.enterText(_field('Email'), 'harper@example.com');
      await tester.pumpAndSettle();
      expect(find.textContaining('whole email address'), findsNothing);
      await _chooseDay(tester, 1);
      expect(find.text('Choose the day of the session.'), findsNothing);
    });

    testWidgets('saves the session and goes straight on to it; back from there skips the form', (tester) async {
      final admin = FakeAdminService();
      await _pumpOver(tester, admin, const SessionFormPage());

      await _fillIn(tester);
      await _choose(tester, 'No package', 'Premium');
      await _choose(tester, 'No time', '6:30 am');
      await tester.enterText(_field('Location (optional)'), ' Liberty Park ');
      await tapInView(tester, find.text('Add session'));
      await tester.pumpAndSettle();

      expect(admin.calls, contains('createSession(The Novak family)'));
      final session = admin.sessions['session-1']!;
      expect(session.name, 'The Novak family');
      expect(session.email, 'novak@example.com');
      expect(session.date, DateTime(now.year, now.month, 15));
      expect(session.packageName, 'Premium');
      expect(session.time, (hour: 6, minute: 30));
      expect(session.location, 'Liberty Park');
      expect(tester.widget<AdminSessionPage>(find.byType(AdminSessionPage)).sessionId, 'session-1');
      expect(find.byType(SessionFormPage), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Below'), findsOneWidget);
    });

    testWidgets('leaves out what isn’t given', (tester) async {
      final admin = FakeAdminService();
      await pumpAdminPage(tester, const SessionFormPage(), admin: admin, size: const Size(1440, 1200));

      await _fillIn(tester);
      await tester.enterText(_field('Location (optional)'), '   ');
      await tapInView(tester, find.text('Add session'));
      await tester.pumpAndSettle();

      final session = admin.sessions['session-1']!;
      expect(session.packageName, isNull);
      expect(session.time, isNull);
      expect(session.location, isNull);
    });

    testWidgets('while saving, the button keeps focus and says so; another press does nothing', (tester) async {
      final admin = FakeAdminService()..writeDelay = const Duration(seconds: 1);
      await pumpAdminPage(tester, const SessionFormPage(), admin: admin, size: const Size(1440, 1200));
      await _fillIn(tester);
      Focus.of(tester.element(find.text('Add session'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Adding session…'), findsOneWidget);
      expect(hasFocus(tester, find.text('Adding session…')), isTrue);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Adding session…')).onPressed, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(admin.calls.where((call) => call.startsWith('createSession')), hasLength(1));
      expect(find.byType(AdminSessionPage), findsOneWidget);
    });

    testWidgets('says why when it isn’t saved, and stays', (tester) async {
      final admin = FakeAdminService()..errors['createSession'] = adminError(AdminErrorKind.offline);
      await pumpAdminPage(tester, const SessionFormPage(), admin: admin, size: const Size(1440, 1200));

      await _fillIn(tester);
      await tapInView(tester, find.text('Add session'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InlineMessage, kAdminOfflineMessage), findsOneWidget);
      expect(find.byType(SessionFormPage), findsOneWidget);
      expect(find.text('Add session'), findsOneWidget);
    });

    testWidgets('trying again after no answer adds the same session, never a second', (tester) async {
      final admin = FakeAdminService()
        ..errors['createSession'] = adminError(AdminErrorKind.offline, kAdminTimedOutMessage);
      await pumpAdminPage(tester, const SessionFormPage(), admin: admin, size: const Size(1440, 1200));

      await _fillIn(tester);
      await tapInView(tester, find.text('Add session'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InlineMessage, kAdminTimedOutMessage), findsOneWidget);

      admin.errors.remove('createSession');
      await tapInView(tester, find.text('Add session'));
      await tester.pumpAndSettle();

      expect(admin.createSessionIds, ['session-1', 'session-1']);
      expect(admin.sessions.keys, ['session-1']);
      expect(tester.widget<AdminSessionPage>(find.byType(AdminSessionPage)).sessionId, 'session-1');
    });

    testWidgets('Cancel goes back without saving', (tester) async {
      final admin = FakeAdminService();
      await _pumpOver(tester, admin, const SessionFormPage());

      await tester.enterText(_field('Name'), 'The Novak family');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Below'), findsOneWidget);
      expect(admin.calls, isEmpty);
    });
  });

  group('the date', () {
    testWidgets('a calendar in a dialog, without openings, from 2020 to a year ahead, opening on today',
        (tester) async {
      await pumpAdminPage(tester, const SessionFormPage(), size: const Size(1440, 1200));

      await tapInView(tester, _dateField());
      await tester.pumpAndSettle();

      expect(find.text('Choose a date'), findsOneWidget);
      final calendar = tester.widget<BookingCalendar>(find.byType(BookingCalendar));
      expect(calendar.showOpenings, isFalse);
      expect(calendar.firstDay, DateTime(2020));
      expect(calendar.lastDay, DateTime(now.year + 1, now.month, now.day));
      expect(calendar.selectedDay, DateTime(now.year, now.month, now.day));
      expect(find.text(formatMonth(now)), findsOneWidget);
      expect(find.text('Openings that day'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cancel keeps the field as it was', (tester) async {
      await pumpAdminPage(tester, const SessionFormPage(), size: const Size(1440, 1200));

      await tapInView(tester, _dateField());
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(BrookieDialog), findsNothing);
      expect(find.text(formatDayShort(DateTime(now.year, now.month, now.day), now: now)), findsNothing);
    });

    testWidgets('a session from before 2020 can keep its day', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(session: testSession('s1', date: DateTime(2018, 5, 6))),
          size: const Size(1440, 1200));

      expect(find.text('Sun, May 6, 2018'), findsOneWidget);
      await tapInView(tester, _dateField());
      await tester.pumpAndSettle();

      final calendar = tester.widget<BookingCalendar>(find.byType(BookingCalendar));
      expect(calendar.firstDay, DateTime(2018, 5, 6));
      expect(find.text('May 2018'), findsOneWidget);
    });

    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      testWidgets('by keyboard: ${key.keyLabel} opens it, and focus comes back to the field', (tester) async {
        await pumpAdminPage(tester, const SessionFormPage(), size: const Size(1440, 1200));
        final field = Focus.of(tester.element(find.text('Date')));
        field.requestFocus();
        await tester.pump();
        // (The field hears of it after the frame that applies it.)
        await tester.pump();
        // Focused, the field shows the theme's focused edge, like a text field.
        expect(tester.widget<InputDecorator>(_dateField()).isFocused, isTrue);

        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(find.text('Choose a date'), findsOneWidget);
        await tester.tap(_inDialog('Use this date'));
        await tester.pumpAndSettle();

        expect(find.text(formatDayShort(DateTime(now.year, now.month, now.day), now: now)), findsOneWidget);
        expect(field.hasPrimaryFocus, isTrue);
      });
    }
  });

  group('editing', () {
    Booking harpers({bool ready = false, ({int hour, int minute})? time = (hour: 6, minute: 15)}) => testSession(
          's1',
          packageName: 'Ultimate',
          date: DateTime(2999, 3, 4),
          time: time,
          location: 'Liberty Park',
          photosReady: ready,
        );

    testWidgets('starts from the session as it is', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(session: harpers()), size: const Size(1440, 1200));

      expect(find.text('Edit session'), findsNWidgets(2));
      expect(find.text('The Harper family'), findsOneWidget);
      expect(find.text('harper@example.com'), findsOneWidget);
      expect(find.text('Ultimate'), findsOneWidget);
      expect(find.text('Mon, Mar 4, 2999'), findsOneWidget);
      expect(find.text('6:15 am'), findsOneWidget);
      expect(find.text('Liberty Park'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save changes'), findsOneWidget);
    });

    testWidgets('a time off the quarter hours is kept on offer', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(session: harpers(time: (hour: 9, minute: 5))),
          size: const Size(1440, 1200));

      expect(find.text('9:05 am'), findsOneWidget);
    });

    testWidgets('saves the changes and goes back', (tester) async {
      final admin = FakeAdminService(sessions: [harpers()]);
      await _pumpOver(tester, admin, SessionFormPage(session: harpers()));

      await tester.enterText(_field('Name'), 'The Harpers');
      await _choose(tester, '6:15 am', 'No time');
      await tapInView(tester, find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(admin.calls, contains('updateSession(s1)'));
      expect(admin.sessions['s1']!.name, 'The Harpers');
      expect(admin.sessions['s1']!.time, isNull);
      expect(admin.sessions['s1']!.packageName, 'Ultimate');
      expect(find.text('Below'), findsOneWidget);
    });

    testWidgets('a new email, with the photos available, asks first', (tester) async {
      final admin = FakeAdminService(sessions: [harpers(ready: true)]);
      await _pumpOver(tester, admin, SessionFormPage(session: harpers(ready: true)));

      await tester.enterText(_field('Email'), 'Grandma@Example.com');
      await tapInView(tester, find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Change who can download?'), findsOneWidget);
      expect(
        find.text('Anyone signed in with Google as grandma@example.com will be able to download these photos, '
            'and harper@example.com won’t.'),
        findsOneWidget,
      );
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();
      expect(admin.calls, isNot(contains('updateSession(s1)')));

      await tapInView(tester, find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Save changes'));
      await tester.pumpAndSettle();
      expect(admin.sessions['s1']!.email, 'grandma@example.com');
      expect(find.text('Below'), findsOneWidget);
    });

    testWidgets('the same email in other letters, or photos not available yet, needs no asking', (tester) async {
      final admin = FakeAdminService(sessions: [harpers(ready: true)]);
      await _pumpOver(tester, admin, SessionFormPage(session: harpers(ready: true)));

      await tester.enterText(_field('Email'), ' Harper@Example.com ');
      await tapInView(tester, find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.byType(BrookieDialog), findsNothing);
      expect(admin.calls, contains('updateSession(s1)'));
    });

    testWidgets('says why when the changes aren’t saved', (tester) async {
      final admin = FakeAdminService(sessions: [harpers()])
        ..errors['updateSession'] = adminError(AdminErrorKind.denied);
      await pumpAdminPage(tester, SessionFormPage(session: harpers()), admin: admin, size: const Size(1440, 1200));

      await tapInView(tester, find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InlineMessage, kAdminDeniedMessage), findsOneWidget);
    });
  });

  for (final brightness in Brightness.values) {
    for (final width in adminTestWidths) {
      testWidgets('fits ${width.toInt()}px in ${brightness.name}, errors and calendar too, with one primary button',
          (tester) async {
        await pumpAdminPage(tester, const SessionFormPage(), brightness: brightness, size: Size(width, 800));
        expect(filledButtons(), 1);

        await tester.enterText(_field('Email'), 'not an email');
        await tapInView(tester, find.text('Add session'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(filledButtons(), 1);

        await tapInView(tester, _dateField());
        await tester.pumpAndSettle();
        expect(find.byType(BookingCalendar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
