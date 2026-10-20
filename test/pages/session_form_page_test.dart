// SessionFormPage: adding an ad hoc session and editing one, the fields and
// what they accept, the date dialog, and saving.

import 'package:brookie_babies/components/booking_calendar.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_details.dart';
import 'package:brookie_babies/pages/admin_session_page.dart';
import 'package:brookie_babies/pages/session_form_page.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/brookie_dialog.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
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

/// The open menu's options.
Finder _options() => find.byType(MenuItemButton);

/// The option labelled [label] in the open menu.
Finder _option(String label) => find.widgetWithText(MenuItemButton, label);

/// The open menu itself: the Material closest around its options.
Finder _menuPanel() => find.ancestor(of: _options().first, matching: find.byType(Material)).first;

/// Whether the option labelled [label] has keyboard focus.
bool _optionHasFocus(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.descendant(of: _option(label), matching: find.text(label)))).hasPrimaryFocus;

/// Whether the field labelled [label] has keyboard focus.
bool _fieldHasFocus(WidgetTester tester, String label) => Focus.of(tester.element(find.text(label))).hasPrimaryFocus;

/// Opens the menu of the field showing [current] and chooses [label] in it.
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
  // Pinned, so a run that crosses midnight or a month reads the same day
  // everywhere. Late in the day, as the clock might be.
  final now = DateTime(2031, 2, 10, 23, 59);

  tearDown(LeaveWarning.reset);

  group('adding', () {
    testWidgets('the fields, what each is for, and the one primary button', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));

      expect(find.text('Add a session'), findsNWidgets(2));
      expect(find.text('For family, friends and anyone not booked on the site. No payment needed.'), findsOneWidget);
      expect(find.text('Who it’s for, such as “The Harper family”.'), findsOneWidget);
      expect(
        find.text('The email they use to sign in to Google. For Gmail, copy it exactly as it appears in '
            'their Google account, dots included.'),
        findsOneWidget,
      );
      expect(find.text('No package'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('No time'), findsOneWidget);
      expect(find.text('Location (optional)'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add session'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(filledButtons(), 1);
    });

    testWidgets('typed text is set in Jost, like the site’s other controls', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now));

      final style =
          tester.widget<EditableText>(find.descendant(of: _field('Name'), matching: find.byType(EditableText))).style;
      expect(style.fontFamily, BrookieType.ui.fontFamily);
      expect(style.fontSize, BrookieType.ui.fontSize);
    });

    testWidgets('packages: none, or one of the three', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));

      await tapInView(tester, find.text('No package'));
      await tester.pumpAndSettle();
      for (final label in ['No package', 'Basic', 'Premium', 'Ultimate']) {
        expect(find.text(label).hitTestable(), findsWidgets);
      }
    });

    testWidgets('times: none, or every quarter hour from 6:00 am to 9:00 pm', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));

      await tapInView(tester, find.text('No time'));
      await tester.pumpAndSettle();
      final labels = [for (final item in tester.widgetList<MenuItemButton>(_options())) (item.child! as Text).data];
      expect(labels.first, 'No time');
      expect(labels[1], '6:00 am');
      expect(labels[2], '6:15 am');
      expect(labels.last, '9:00 pm');
      expect(labels, hasLength(1 + 15 * 4 + 1));
      expect(labels, contains('12:00 pm'));
    });

    testWidgets('empty: says what each required field needs, and focuses the first', (tester) async {
      final admin = FakeAdminService();
      await pumpAdminPage(tester, SessionFormPage(now: now), admin: admin, size: const Size(1440, 1200));

      await tester.tap(find.text('Add session'));
      await tester.pumpAndSettle();

      expect(find.text('Enter who the session is for.'), findsOneWidget);
      expect(find.text('Enter the email they use to sign in to Google.'), findsOneWidget);
      expect(find.text('Choose the day of the session.'), findsOneWidget);
      expect(admin.calls, isEmpty);
      expect(tester.widget<EditableText>(find.descendant(of: _field('Name'), matching: find.byType(EditableText)))
          .focusNode.hasFocus, isTrue);
    });

    testWidgets('a missing date, out of view, is scrolled to as it’s focused', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(390, 300));
      await tester.enterText(_field('Name'), 'The Novak family');
      await tester.enterText(_field('Email'), 'novak@example.com');
      // Or the email field, focused, keeps itself in view, and scrolls back
      // to itself once its caret's scroll has run.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add session'));
      await tester.pumpAndSettle();
      final view = tester.getRect(find.byType(Scrollable).first);
      expect(tester.getRect(_dateField()).bottom, lessThan(view.top), reason: 'starts out of view');

      await tester.tap(find.text('Add session'));
      await tester.pumpAndSettle();

      expect(Focus.of(tester.element(find.text('Date'))).hasPrimaryFocus, isTrue);
      final field = tester.getRect(_dateField());
      expect(field.top, greaterThanOrEqualTo(view.top));
      expect(field.bottom, lessThanOrEqualTo(view.bottom));
      expect(find.text('Choose the day of the session.').hitTestable(), findsOneWidget);
    });

    testWidgets('checks each field against what the rules accept, and clears as it’s fixed', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));

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

    testWidgets('refuses an email no Google sign-in could match, saying how to fix it', (tester) async {
      final admin = FakeAdminService();
      await pumpAdminPage(tester, SessionFormPage(now: now), admin: admin, size: const Size(1440, 1200));
      await _fillIn(tester);

      for (final (email, says) in [
        ('<novak@example.com>', 'An email address has no < or >. Enter just the address, like name@gmail.com.'),
        (
          'mailto:novak@example.com',
          '“mailto:” isn’t part of the address. Enter just the address, like name@gmail.com.',
        ),
        ('no vak@example.com', 'That has a space in it. Take it out: an email address has none.'),
        (
          'novak+photos@gmail.com',
          '“+photos” isn’t part of a Gmail address: Google signs them in without it. Take it out.',
        ),
      ]) {
        await tester.enterText(_field('Email'), email);
        await tapInView(tester, find.text('Add session'));
        await tester.pumpAndSettle();
        expect(find.text(says), findsOneWidget, reason: email);
      }
      expect(admin.calls, isEmpty);

      // A tag on another domain may be how their Google account is named.
      await tester.enterText(_field('Email'), 'novak+photos@example.com');
      await tapInView(tester, find.text('Add session'));
      await tester.pumpAndSettle();
      expect(admin.sessions.values.single.email, 'novak+photos@example.com');
    });

    testWidgets('saves the session and goes straight on to it; back from there skips the form', (tester) async {
      final admin = FakeAdminService();
      await _pumpOver(tester, admin, SessionFormPage(now: now));

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
      await pumpAdminPage(tester, SessionFormPage(now: now), admin: admin, size: const Size(1440, 1200));

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
      await pumpAdminPage(tester, SessionFormPage(now: now), admin: admin, size: const Size(1440, 1200));
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
      await pumpAdminPage(tester, SessionFormPage(now: now), admin: admin, size: const Size(1440, 1200));

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
      await pumpAdminPage(tester, SessionFormPage(now: now), admin: admin, size: const Size(1440, 1200));

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

    testWidgets('trying again after no answer, with the email fixed, saves the fixed email', (tester) async {
      final admin = _SavedButNoAnswer();
      await pumpAdminPage(tester, SessionFormPage(now: now), admin: admin, size: const Size(1440, 1200));

      await _fillIn(tester);
      await tester.enterText(_field('Email'), 'novka@example.com');
      await tapInView(tester, find.text('Add session'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InlineMessage, kAdminTimedOutMessage), findsOneWidget);
      expect(admin.sessions['session-1']!.email, 'novka@example.com');

      await tester.enterText(_field('Email'), 'novak@example.com');
      await tapInView(tester, find.text('Add session'));
      await tester.pumpAndSettle();

      expect(admin.createSessionIds, ['session-1', 'session-1']);
      expect(admin.sessions.keys, ['session-1']);
      expect(admin.sessions['session-1']!.email, 'novak@example.com');
      expect(tester.widget<AdminSessionPage>(find.byType(AdminSessionPage)).sessionId, 'session-1');
    });

    testWidgets('Cancel, untouched, goes straight back', (tester) async {
      final admin = FakeAdminService();
      await _pumpOver(tester, admin, SessionFormPage(now: now));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(BrookieDialog), findsNothing);
      expect(find.text('Below'), findsOneWidget);
      expect(admin.calls, isEmpty);
    });
  });

  group('leaving with changes', () {
    testWidgets('anything typed or chosen: warns the browser and asks first, by Cancel or back', (tester) async {
      final admin = FakeAdminService();
      await _pumpOver(tester, admin, SessionFormPage(now: now));
      expect(tester.widget<BrookieTopBar>(find.byType(BrookieTopBar)).showSessionsLink, isFalse);
      expect(LeaveWarning.active.value, isFalse);

      await tester.enterText(_field('Name'), 'The Novak family');
      await tester.pump();
      expect(LeaveWarning.active.value, isTrue);

      for (final leave in [find.text('Cancel'), find.byTooltip('Back')]) {
        await tester.tap(leave);
        await tester.pumpAndSettle();
        expect(find.text('Leave without saving?'), findsOneWidget);
        expect(find.text('The session you started adding will be lost.'), findsOneWidget);
        await tester.tap(_inDialog('Keep editing'));
        await tester.pumpAndSettle();
        expect(find.byType(SessionFormPage), findsOneWidget);
        expect(find.text('The Novak family'), findsOneWidget);
      }

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Leave without saving'));
      await tester.pumpAndSettle();
      expect(find.text('Below'), findsOneWidget);
      expect(LeaveWarning.active.value, isFalse);
      expect(admin.calls, isEmpty);
    });

    testWidgets('a choice counts, and undoing every change needs no asking', (tester) async {
      await _pumpOver(tester, FakeAdminService(), SessionFormPage(now: now));

      await _choose(tester, 'No package', 'Basic');
      expect(LeaveWarning.active.value, isTrue);
      await _choose(tester, 'Basic', 'No package');
      await tester.enterText(_field('Email'), 'a');
      await tester.enterText(_field('Email'), '');
      await tester.pump();
      expect(LeaveWarning.active.value, isFalse);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Below'), findsOneWidget);
    });

    testWidgets('the date counts too', (tester) async {
      await _pumpOver(tester, FakeAdminService(), SessionFormPage(now: now));

      await _chooseDay(tester, 15);

      expect(LeaveWarning.active.value, isTrue);
    });

    testWidgets('editing: asks about the changes, and leaves the session as it was', (tester) async {
      final session = testSession('s1', location: 'Liberty Park');
      final admin = FakeAdminService(sessions: [session]);
      await _pumpOver(tester, admin, SessionFormPage(now: now, session: session));
      expect(LeaveWarning.active.value, isFalse);

      await tester.enterText(_field('Location (optional)'), 'The studio');
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('The changes you made to this session will be lost.'), findsOneWidget);
      await tester.tap(_inDialog('Leave without saving'));
      await tester.pumpAndSettle();

      expect(find.text('Below'), findsOneWidget);
      expect(admin.sessions['s1']!.location, 'Liberty Park');
    });

    testWidgets('once saved, nothing to lose: no asking, no warning', (tester) async {
      final admin = FakeAdminService(sessions: [testSession('s1')]);
      await _pumpOver(tester, admin, SessionFormPage(now: now, session: testSession('s1')));

      await tester.enterText(_field('Name'), 'The Harpers');
      await tapInView(tester, find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.byType(BrookieDialog), findsNothing);
      expect(find.text('Below'), findsOneWidget);
      expect(LeaveWarning.active.value, isFalse);
    });

    testWidgets('a save that fails keeps the warning', (tester) async {
      final admin = FakeAdminService()..errors['createSession'] = adminError(AdminErrorKind.offline);
      await pumpAdminPage(tester, SessionFormPage(now: now), admin: admin, size: const Size(1440, 1200));

      await _fillIn(tester);
      await tapInView(tester, find.text('Add session'));
      await tester.pumpAndSettle();

      expect(LeaveWarning.active.value, isTrue);
    });

    testWidgets('adding: once saved, on to the session with the warning off', (tester) async {
      final admin = FakeAdminService();
      await _pumpOver(tester, admin, SessionFormPage(now: now));

      await _fillIn(tester);
      await tapInView(tester, find.text('Add session'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminSessionPage), findsOneWidget);
      expect(LeaveWarning.active.value, isFalse);
    });
  });

  group('leaving while it saves', () {
    /// Starts saving with [label], then asks to leave with [leave].
    Future<void> saveThenAsk(WidgetTester tester, String label, {Finder? leave}) async {
      await tapInView(tester, find.text(label));
      await tester.pump();
      await tester.tap(leave ?? find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('adding: says the session will still be added, and it is', (tester) async {
      final admin = FakeAdminService()..writeDelay = const Duration(seconds: 5);
      await _pumpOver(tester, admin, SessionFormPage(now: now));
      await _fillIn(tester);

      await saveThenAsk(tester, 'Add session');
      expect(find.text('Leave while saving?'), findsOneWidget);
      expect(
        find.text('The session is still being added. If you leave now, it’ll still be added, but you won’t see it '
            'if adding it fails.'),
        findsOneWidget,
      );
      await tester.tap(_inDialog('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Below'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(admin.sessions.keys, ['session-1']);
      expect(find.text('Below'), findsOneWidget);
      expect(find.byType(AdminSessionPage), findsNothing);
    });

    testWidgets('editing: says the changes will still be saved, and they are', (tester) async {
      final session = testSession('s1', location: 'Liberty Park');
      final admin = FakeAdminService(sessions: [session])..writeDelay = const Duration(seconds: 5);
      await _pumpOver(tester, admin, SessionFormPage(now: now, session: session));
      await tester.enterText(_field('Location (optional)'), 'The studio');

      await saveThenAsk(tester, 'Save changes', leave: find.byTooltip('Back'));
      expect(find.text('Leave while saving?'), findsOneWidget);
      expect(
        find.text('Your changes are still saving. If you leave now, they’ll still be saved, but you won’t see it if '
            'saving fails.'),
        findsOneWidget,
      );
      await tester.tap(_inDialog('Leave'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(admin.sessions['s1']!.location, 'The studio');
      expect(find.text('Below'), findsOneWidget);
    });

    testWidgets('adding: a save that answers as the form goes replaces nothing', (tester) async {
      final admin = FakeAdminService()..writeDelay = const Duration(seconds: 1);
      final navigator = await _pumpOver(tester, admin, SessionFormPage(now: now));
      await _fillIn(tester);

      await saveThenAsk(tester, 'Add session');
      await tester.tap(_inDialog('Leave'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // The save answers while the form is still on its way out.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(admin.sessions.keys, ['session-1']);
      expect(find.byType(AdminSessionPage), findsNothing);
      expect(find.text('Below'), findsOneWidget);
      expect(navigator.canPop(), isFalse);
    });

    testWidgets('editing: a save that answers as the form goes leaves the session page and its uploads',
        (tester) async {
      final admin = FakeAdminService(sessions: [testSession('s1')], sessionPhotos: {
        's1': ['a.jpg'],
      });
      final picker = FakePhotoPicker()..next = [testPhoto('b.jpg')];
      await pumpAdminPage(tester, const Scaffold(body: Text('Below')),
          admin: admin, picker: picker, size: const Size(1440, 1200));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(MaterialPageRoute<void>(builder: (context) => const AdminSessionPage(sessionId: 's1')));
      await tester.pumpAndSettle();
      await tapInView(tester, find.text('Upload photos'));
      await tester.pump();
      await tester.pump();
      expect(admin.pendingUploads, hasLength(1));

      await tapInView(tester, find.text('Edit details'));
      await tester.pumpAndSettle();
      admin.writeDelay = const Duration(seconds: 1);
      await tester.enterText(_field('Location (optional)'), 'The studio');
      await saveThenAsk(tester, 'Save changes');
      await tester.tap(_inDialog('Leave'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // The save answers while the form is still on its way out.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(admin.sessions['s1']!.location, 'The studio');
      expect(find.byType(AdminSessionPage), findsOneWidget);
      expect(admin.uploads.single.cancelled, isFalse);
      expect(admin.pendingUploads, hasLength(1));
    });

    testWidgets('staying: a save that answered meanwhile goes on to the session', (tester) async {
      final admin = FakeAdminService()..writeDelay = const Duration(seconds: 1);
      await _pumpOver(tester, admin, SessionFormPage(now: now));
      await _fillIn(tester);

      await saveThenAsk(tester, 'Add session');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      // Not while it asks: the dialog is on top.
      expect(find.text('Leave while saving?'), findsOneWidget);
      expect(find.byType(AdminSessionPage), findsNothing);
      await tester.tap(_inDialog('Stay'));
      await tester.pumpAndSettle();

      expect(tester.widget<AdminSessionPage>(find.byType(AdminSessionPage)).sessionId, 'session-1');
      expect(find.byType(SessionFormPage), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Below'), findsOneWidget);
    });

    testWidgets('staying while it saves: once saved, back to the session', (tester) async {
      final session = testSession('s1');
      final admin = FakeAdminService(sessions: [session])..writeDelay = const Duration(seconds: 1);
      await _pumpOver(tester, admin, SessionFormPage(now: now, session: session));
      await tester.enterText(_field('Name'), 'The Harpers');

      await saveThenAsk(tester, 'Save changes');
      await tester.tap(_inDialog('Stay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BrookieDialog), findsNothing);
      expect(find.text('Saving changes…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(admin.sessions['s1']!.name, 'The Harpers');
      expect(find.text('Below'), findsOneWidget);
    });
  });

  group('the package and time menus', () {
    for (final brightness in Brightness.values) {
      testWidgets('in ${brightness.name}: no shadow, a line-strong edge, as wide as the field', (tester) async {
        final c = brightness == Brightness.dark ? BrookieColors.dark : BrookieColors.light;
        await pumpAdminPage(tester, SessionFormPage(now: now), brightness: brightness, size: const Size(1440, 1200));

        await tapInView(tester, find.text('No package'));
        await tester.pumpAndSettle();

        final style =
            tester.widget<MenuAnchor>(find.ancestor(of: find.text('Package'), matching: find.byType(MenuAnchor))).style!;
        expect(style.elevation!.resolve({}), 0);
        expect(style.side!.resolve({}), BorderSide(color: c.lineStrong));
        expect(style.backgroundColor!.resolve({}), c.surface);
        expect(
          style.shape!.resolve({}),
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrookieRadius.md)),
        );
        // Nothing in the open menu casts a shadow.
        for (final material in tester.widgetList<Material>(
            find.ancestor(of: _option('Basic'), matching: find.byType(Material)))) {
          expect(material.elevation, 0);
        }
        final field = tester.getRect(find.ancestor(of: find.text('Package'), matching: find.byType(InputDecorator)));
        final panel = tester.getRect(_menuPanel());
        expect(panel.width, field.width);
        expect(panel.top, greaterThan(field.bottom));
        // The chosen option is ticked.
        expect(find.descendant(of: _option('No package'), matching: find.byIcon(Icons.check)), findsOneWidget);
        expect(find.descendant(of: _option('Basic'), matching: find.byIcon(Icons.check)), findsNothing);
      });
    }

    testWidgets('opens at once, without animating', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));
      await tester.ensureVisible(find.text('No time'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('No time'));
      await tester.pump();
      final first = tester.getRect(_option('6:00 am'));
      expect(_option('6:00 am').hitTestable(), findsOneWidget);
      await tester.pumpAndSettle();

      expect(tester.getRect(_option('6:00 am')), first);
    });

    testWidgets('the keyboard opens it on the chosen option, moves, wraps, chooses and comes back', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));
      Focus.of(tester.element(find.text('Package'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_optionHasFocus(tester, 'No package'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_optionHasFocus(tester, 'Premium'), isTrue);
      // A ring, not Material's faint band.
      final item = tester.widget<MenuItemButton>(_option('Premium'));
      expect(item.style!.side!.resolve({WidgetState.focused}), brookieFocusSide(BrookieColors.light.focus));
      expect(item.style!.overlayColor!.resolve({WidgetState.focused}), Colors.transparent);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(_optionHasFocus(tester, 'Ultimate'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_optionHasFocus(tester, 'No package'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_options(), findsNothing);
      expect(find.text('Ultimate'), findsOneWidget);
      expect(_fieldHasFocus(tester, 'Package'), isTrue);
    });

    testWidgets('Escape closes it, choosing nothing, with focus back on the field', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));
      Focus.of(tester.element(find.text('Package'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(_options(), findsNothing);
      expect(find.text('No package'), findsOneWidget);
      expect(_fieldHasFocus(tester, 'Package'), isTrue);
    });

    testWidgets('a click opens it without moving focus into it; a click outside closes it', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));

      await tapInView(tester, find.text('No package'));
      await tester.pumpAndSettle();
      expect(_options(), findsNWidgets(4));
      expect(_fieldHasFocus(tester, 'Package'), isTrue);

      await tester.tapAt(const Offset(1400, 1150));
      await tester.pumpAndSettle();
      expect(_options(), findsNothing);
      expect(find.text('No package'), findsOneWidget);
    });

    testWidgets('opening on a time far down the menu leaves the page where it was', (tester) async {
      await pumpAdminPage(
        tester,
        SessionFormPage(now: now, session: testSession('s1', time: (hour: 20, minute: 45))),
        size: const Size(390, 700),
      );
      await tester.ensureVisible(find.text('8:45 pm'));
      await tester.pumpAndSettle();
      final page = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      final before = page.pixels;
      expect(before, greaterThan(0));
      final field = tester.getRect(find.text('8:45 pm'));

      for (final open in [
        () => tester.tap(find.text('8:45 pm')),
        () async {
          Focus.of(tester.element(find.text('Time'))).requestFocus();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        },
      ]) {
        await open();
        await tester.pumpAndSettle();
        expect(_option('8:45 pm').hitTestable(), findsOneWidget);
        expect(page.pixels, before);
        expect(tester.getRect(find.text('8:45 pm').first), field);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.tapAt(const Offset(380, 690));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('the time menu scrolls, and opens on the chosen time', (tester) async {
      await pumpAdminPage(
        tester,
        SessionFormPage(now: now, session: testSession('s1', time: (hour: 18, minute: 15))),
        size: const Size(1440, 1200),
      );

      await tapInView(tester, find.text('6:15 pm'));
      await tester.pumpAndSettle();

      final panel = tester.getRect(_menuPanel());
      expect(panel.height, lessThanOrEqualTo(360));
      expect(_option('6:15 pm').hitTestable(), findsOneWidget);
      expect(_option('No time').hitTestable(), findsNothing);
    });
  });

  group('the date', () {
    testWidgets('a calendar in a dialog, without openings, from 2020 to a year ahead, opening on today',
        (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));

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

    testWidgets('today is the page’s clock, in the calendar and the field', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: DateTime(2033, 7, 1, 0, 0, 1)), size: const Size(1440, 1200));

      await tapInView(tester, _dateField());
      await tester.pumpAndSettle();
      final calendar = tester.widget<BookingCalendar>(find.byType(BookingCalendar));
      expect(calendar.today, DateTime(2033, 7, 1, 0, 0, 1));
      expect(calendar.lastDay, DateTime(2034, 7, 1));
      expect(find.text('July 2033'), findsOneWidget);
      await tester.tap(_inDialog('Use this date'));
      await tester.pumpAndSettle();

      // This year's day, so without the year.
      expect(find.text('Fri, Jul 1'), findsOneWidget);
    });

    for (final width in adminTestWidths) {
      testWidgets('${width.toInt()}px wide: full-size days with room for their rings', (tester) async {
        await pumpAdminPage(tester, SessionFormPage(now: now), size: Size(width, 800));

        await tapInView(tester, _dateField());
        await tester.pumpAndSettle();

        final page = tester.getRect(find.descendant(of: find.byType(BookingCalendar), matching: find.byType(PageView)));
        expect(page.left, greaterThanOrEqualTo(0));
        expect(page.right, lessThanOrEqualTo(width));
        for (var day = 1; day <= 28; day++) {
          final disc = tester.getRect(find
              .ancestor(
                of: find.descendant(of: find.byType(BookingCalendar), matching: find.text('$day')),
                matching: find.byType(AnimatedContainer),
              )
              .first);
          expect(disc.width, moreOrLessEquals(BrookieSize.day, epsilon: 0.01), reason: '$day');
          expect(disc.height, moreOrLessEquals(BrookieSize.day, epsilon: 0.01), reason: '$day');
          final ring = disc.inflate(4);
          expect(ring.left >= page.left && ring.right <= page.right && ring.bottom <= page.bottom, isTrue,
              reason: 'ring around $day ($ring) inside the month page ($page)');
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Cancel keeps the field as it was', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));

      await tapInView(tester, _dateField());
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(BrookieDialog), findsNothing);
      expect(find.text(formatDayShort(DateTime(now.year, now.month, now.day), now: now)), findsNothing);
    });

    testWidgets('a session from before 2020 can keep its day', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now, session: testSession('s1', date: DateTime(2018, 5, 6))),
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
        await pumpAdminPage(tester, SessionFormPage(now: now), size: const Size(1440, 1200));
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
      await pumpAdminPage(tester, SessionFormPage(now: now, session: harpers()), size: const Size(1440, 1200));

      expect(find.text('Edit session'), findsNWidgets(2));
      expect(find.text('The Harper family'), findsOneWidget);
      expect(find.text('harper@example.com'), findsOneWidget);
      expect(find.text('Ultimate'), findsOneWidget);
      expect(find.text('Mon, Mar 4, 2999'), findsOneWidget);
      expect(find.text('6:15 am'), findsOneWidget);
      expect(find.text('Liberty Park'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save changes'), findsOneWidget);
    });

    testWidgets('a package typed in the console is kept on offer, and kept on saving', (tester) async {
      final odd = testSession('s1', packageName: 'premium');
      final admin = FakeAdminService(sessions: [odd]);
      await _pumpOver(tester, admin, SessionFormPage(now: now, session: odd));

      expect(find.text('premium'), findsOneWidget);
      await tapInView(tester, find.text('premium'));
      await tester.pumpAndSettle();
      expect(
        [for (final item in tester.widgetList<MenuItemButton>(_options())) (item.child! as Text).data],
        ['No package', 'Basic', 'Premium', 'Ultimate', 'premium'],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.tapAt(const Offset(1400, 1150));
      await tester.pumpAndSettle();
      expect(LeaveWarning.active.value, isFalse);

      await tester.enterText(_field('Location (optional)'), 'The studio');
      await tapInView(tester, find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(admin.sessions['s1']!.packageName, 'premium');
      expect(admin.sessions['s1']!.location, 'The studio');
    });

    testWidgets('a time off the quarter hours is kept on offer', (tester) async {
      await pumpAdminPage(tester, SessionFormPage(now: now, session: harpers(time: (hour: 9, minute: 5))),
          size: const Size(1440, 1200));

      expect(find.text('9:05 am'), findsOneWidget);
    });

    testWidgets('saves the changes and goes back', (tester) async {
      final admin = FakeAdminService(sessions: [harpers()]);
      await _pumpOver(tester, admin, SessionFormPage(now: now, session: harpers()));

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
      await _pumpOver(tester, admin, SessionFormPage(now: now, session: harpers(ready: true)));

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
      await _pumpOver(tester, admin, SessionFormPage(now: now, session: harpers(ready: true)));

      await tester.enterText(_field('Email'), ' Harper@Example.com ');
      await tapInView(tester, find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.byType(BrookieDialog), findsNothing);
      expect(admin.calls, contains('updateSession(s1)'));
    });

    testWidgets('says why when the changes aren’t saved', (tester) async {
      final admin = FakeAdminService(sessions: [harpers()])
        ..errors['updateSession'] = adminError(AdminErrorKind.denied);
      await pumpAdminPage(tester, SessionFormPage(now: now, session: harpers()),
          admin: admin, size: const Size(1440, 1200));

      await tapInView(tester, find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InlineMessage, kAdminDeniedMessage), findsOneWidget);
    });
  });

  for (final brightness in Brightness.values) {
    for (final width in adminTestWidths) {
      testWidgets('fits ${width.toInt()}px in ${brightness.name}, errors and calendar too, with one primary button',
          (tester) async {
        await pumpAdminPage(tester, SessionFormPage(now: now), brightness: brightness, size: Size(width, 800));
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
        await tester.tap(_inDialog('Cancel'));
        await tester.pumpAndSettle();

        await tapInView(tester, find.text('No time'));
        await tester.pumpAndSettle();
        expect(_option('6:00 am').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

/// A FakeAdminService whose first createSession is saved but answers too
/// late, as FirebaseAdminService reports a write after its time limit.
class _SavedButNoAnswer extends FakeAdminService {
  var _answered = false;

  @override
  Future<String> createSession(SessionDetails details, {String? id}) async {
    final saved = await super.createSession(details, id: id);
    if (_answered) return saved;
    _answered = true;
    throw adminError(AdminErrorKind.offline, kAdminTimedOutMessage);
  }
}
