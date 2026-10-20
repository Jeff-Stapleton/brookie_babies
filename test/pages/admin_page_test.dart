// AdminPage's body: the home page photos card, the sessions (upcoming,
// past, unreadable) and the ways on from them. Its frame, navigation and
// notice are in admin_pages_test.dart.

import 'package:brookie_babies/components/admin_session_card.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_lookup.dart';
import 'package:brookie_babies/pages/admin_page.dart';
import 'package:brookie_babies/pages/admin_session_page.dart';
import 'package:brookie_babies/pages/home_photos_admin_page.dart';
import 'package:brookie_babies/pages/session_form_page.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/empty_state.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/admin_test_app.dart';
import '../support/fakes.dart';

/// Sessions at every point: upcoming (out of order), past, paid and not.
FakeAdminService _sample() => FakeAdminService(sessions: [
      testSession('later', name: 'The Okafor twins', date: DateTime(2999, 12, 31)),
      testSession('old', name: 'Grandma Jo', date: DateTime(2001, 1, 2), photosReady: true),
      testSession('soon', date: DateTime(2999, 3, 4), time: (hour: 14, minute: 30)),
      testSession(
        'paid',
        name: null,
        email: 'parent@example.com',
        status: BookingStatus.paid,
        date: DateTime(2010, 6, 7),
      ),
    ]);

/// The card for [id].
Finder _card(String id) => find.byKey(ValueKey(id));

void main() {
  tearDown(AdminPage.clearNotice);

  testWidgets('lists upcoming sessions soonest first, then past ones newest first', (tester) async {
    await pumpAdminPage(tester, const AdminPage(), admin: _sample());

    final cards = tester.widgetList<AdminSessionCard>(find.byType(AdminSessionCard)).map((c) => c.booking.id);
    expect(cards, ['soon', 'later', 'paid', 'old']);
    expect(tester.getTopLeft(find.text('Upcoming')).dy, lessThan(tester.getTopLeft(_card('soon')).dy));
    expect(tester.getTopLeft(find.text('Past')).dy, greaterThan(tester.getTopLeft(_card('later')).dy));
    expect(tester.getTopLeft(find.text('Past')).dy, lessThan(tester.getTopLeft(_card('paid')).dy));
  });

  testWidgets('a card names who it’s for, the package, the day and time, and both tags', (tester) async {
    await pumpAdminPage(tester, const AdminPage(), admin: _sample());

    final soon = _card('soon');
    expect(find.descendant(of: soon, matching: find.text('The Harper family')), findsOneWidget);
    expect(find.descendant(of: soon, matching: find.text('Photo session')), findsOneWidget);
    expect(find.descendant(of: soon, matching: find.text('Mon, Mar 4, 2999')), findsOneWidget);
    expect(find.descendant(of: soon, matching: find.text('2:30 pm')), findsOneWidget);
    expect(find.descendant(of: soon, matching: find.text('Ad hoc')), findsOneWidget);
    expect(find.descendant(of: soon, matching: find.text('Not ready')), findsOneWidget);

    // A booking has no name: its email stands in.
    final paid = _card('paid');
    expect(find.descendant(of: paid, matching: findDisplayName('parent@example.com')), findsOneWidget);
    expect(find.descendant(of: paid, matching: find.text('Premium session')), findsOneWidget);
    expect(find.descendant(of: paid, matching: find.text('Paid')), findsOneWidget);

    final ready = tester.widget<StatusTag>(
        find.descendant(of: _card('old'), matching: find.widgetWithText(StatusTag, 'Ready to download')));
    expect(ready.tone, StatusTone.success);
  });

  testWidgets('a session with neither name nor email is just "Session"', (tester) async {
    await pumpAdminPage(tester, const AdminPage(),
        admin: FakeAdminService(sessions: [
          testSession('x', name: null, email: null, status: BookingStatus.paid),
        ]));

    expect(find.descendant(of: _card('x'), matching: find.text('Session')), findsOneWidget);
  });

  testWidgets('shows sessions added or changed while it’s open', (tester) async {
    final admin = _sample();
    await pumpAdminPage(tester, const AdminPage(), admin: admin);

    admin.sessions['new'] = testSession('new', name: 'The Novak family', date: DateTime(2999, 1, 1));
    admin.notifyChanged();
    await tester.pumpAndSettle();

    expect(find.text('The Novak family'), findsOneWidget);
    expect(admin.calls.where((call) => call == 'watchSessions()'), hasLength(1));
  });

  testWidgets('no sessions: the shared empty band, under the one primary button', (tester) async {
    await pumpAdminPage(tester, const AdminPage());

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.textContaining('No sessions yet.'), findsOneWidget);
    expect(filledButtons(), 1);
    expect(find.widgetWithText(FilledButton, 'Add a session'), findsOneWidget);
  });

  testWidgets('unreadable documents: how many, and each id (selectable) with its problem', (tester) async {
    await pumpAdminPage(tester, const AdminPage(),
        admin: FakeAdminService(unreadable: [
          const UnreadableBooking(
            id: 'abc123',
            problem: 'date isn’t YYYY-MM-DD',
            email: 'x@example.com',
            date: '2026-2-3',
          ),
        ]));

    expect(find.widgetWithText(InlineMessage, '1 session couldn’t be read. Fix it in the Firestore console.'),
        findsOneWidget);
    expect(find.widgetWithText(SelectableText, 'abc123'), findsOneWidget);
    expect(find.text('date isn’t YYYY-MM-DD'), findsOneWidget);
    expect(find.text('x@example.com · 2026-2-3'), findsOneWidget);
    // Only unreadable ones: they aren't "no sessions".
    expect(find.byType(EmptyState), findsNothing);
  });

  testWidgets('several unreadable documents are counted, alongside the readable ones', (tester) async {
    final admin = _sample()
      ..unreadable.addAll(const [
        UnreadableBooking(id: 'a', problem: 'packageName is missing'),
        UnreadableBooking(id: 'b', problem: 'status isn’t paid, pending, cancelled, refunded or adhoc'),
        UnreadableBooking(id: 'c', problem: 'date isn’t a real day'),
      ]);
    await pumpAdminPage(tester, const AdminPage(), admin: admin);

    expect(find.text('3 sessions couldn’t be read. Fix them in the Firestore console.'), findsOneWidget);
    for (final id in ['a', 'b', 'c']) {
      expect(find.widgetWithText(SelectableText, id), findsOneWidget);
    }
    expect(find.byType(AdminSessionCard), findsNWidgets(4));
  });

  testWidgets('says so when the sessions can’t be loaded', (tester) async {
    await pumpAdminPage(tester, const AdminPage(),
        admin: FakeAdminService()..watchError = adminError(AdminErrorKind.denied));

    expect(find.widgetWithText(InlineMessage, 'We couldn’t load the sessions. Refresh the page to try again.'),
        findsOneWidget);
  });

  testWidgets('asks for the sessions only once the gate has let an admin in', (tester) async {
    final admin = _sample();
    await pumpAdminPage(tester, const AdminPage(), admin: admin, auth: FakeAuthService(signedInAs: testUser));

    expect(find.textContaining('isn’t an admin'), findsOneWidget);
    expect(admin.calls, isEmpty);
  });

  group('ways on', () {
    testWidgets('"Add a session" opens the form, and clears the notice', (tester) async {
      await pumpAdminPage(tester, const AdminPage(), admin: _sample());
      AdminPage.returnWithNotice(tester.element(find.byType(AdminPage)), 'Saved.');
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);

      await tester.tap(find.text('Add a session'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionFormPage), findsOneWidget);
      expect(tester.widget<SessionFormPage>(find.byType(SessionFormPage)).session, isNull);
      expect(AdminPage.notice.value, isNull);
    });

    testWidgets('"Edit home page photos" opens the home page photos', (tester) async {
      await pumpAdminPage(tester, const AdminPage());

      expect(find.widgetWithText(OutlinedButton, 'Edit home page photos'), findsOneWidget);
      await tester.tap(find.text('Edit home page photos'));
      await tester.pumpAndSettle();

      expect(find.byType(HomePhotosAdminPage), findsOneWidget);
    });

    testWidgets('a card opens its session', (tester) async {
      await pumpAdminPage(tester, const AdminPage(), admin: _sample());

      await tapInView(tester, _card('paid'));
      await tester.pumpAndSettle();

      expect(tester.widget<AdminSessionPage>(find.byType(AdminSessionPage)).sessionId, 'paid');
    });

    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      testWidgets('by keyboard: Tab reaches a card, which rings itself, and ${key.keyLabel} opens it',
          (tester) async {
        await pumpAdminPage(tester, const AdminPage(), admin: _sample());

        // Account menu, "Edit home page photos", "Add a session", then the first card.
        for (var i = 0; i < 4; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        }
        await tester.pumpAndSettle();
        final ring = find.descendant(of: _card('soon'), matching: find.byType(FocusRing));
        expect(tester.widget<FocusRing>(ring).visible, isTrue);
        expect(tester.widget<FocusRing>(find.descendant(of: _card('later'), matching: find.byType(FocusRing))).visible,
            isFalse);

        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(tester.widget<AdminSessionPage>(find.byType(AdminSessionPage)).sessionId, 'soon');
      });
    }

    testWidgets('a card is one button for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpAdminPage(tester, const AdminPage(), admin: _sample());

      expect(
        tester.getSemantics(_card('soon')),
        matchesSemantics(
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: 'The Harper family\nPhoto session\nMon, Mar 4, 2999\n2:30 pm\nAd hoc\nNot ready',
        ),
      );
      semantics.dispose();
    });
  });

  group('the notice', () {
    testWidgets('sits under the headline, and brings the page back to the top', (tester) async {
      final admin = FakeAdminService(sessions: [
        for (var i = 0; i < 12; i++) testSession('s$i', name: 'Family $i', date: DateTime(2999, 1, i + 1)),
      ]);
      await pumpAdminPage(tester, const AdminPage(), admin: admin, size: const Size(390, 844));
      await tester.scrollUntilVisible(_card('s11'), 300);
      await tester.pumpAndSettle();
      final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).controller!;
      expect(scroll.offset, greaterThan(0));

      AdminPage.returnWithNotice(tester.element(find.byType(AdminPage)), 'Deleted the Harper family’s session.');
      await tester.pumpAndSettle();

      expect(scroll.offset, 0);
      final notice = find.widgetWithText(InlineMessage, 'Deleted the Harper family’s session.');
      expect(tester.getTopLeft(notice).dy, greaterThan(tester.getBottomLeft(find.text('Admin').last).dy));
    });
  });

  for (final brightness in Brightness.values) {
    for (final width in adminTestWidths) {
      testWidgets('fits ${width.toInt()}px in ${brightness.name}, with one primary button', (tester) async {
        final admin = _sample()
          ..unreadable.add(
              const UnreadableBooking(id: 'aVeryLongDocumentId0123456789', problem: 'date isn’t YYYY-MM-DD'))
          ..sessions['long'] = testSession('long',
              name: null, email: 'a.very.long.address.for.a.family@example.com', status: BookingStatus.pending);
        await pumpAdminPage(tester, const AdminPage(), admin: admin, brightness: brightness, size: Size(width, 800));
        AdminPage.returnWithNotice(tester.element(find.byType(AdminPage)), 'Deleted the Harper family’s session.');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(filledButtons(), 1);
        expect(BrookieColors.of(tester.element(find.byType(AdminPage))).paper,
            brightness == Brightness.dark ? BrookieColors.dark.paper : BrookieColors.light.paper);
      });
    }
  }
}
