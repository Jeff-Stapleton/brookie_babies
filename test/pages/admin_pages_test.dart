// The admin pages' frame (the shared top bar without the "Admin" link, and
// the gate), and AdminPage's navigation and notice.

import 'package:brookie_babies/components/admin_gate.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/admin_page.dart';
import 'package:brookie_babies/pages/admin_session_page.dart';
import 'package:brookie_babies/pages/home_photos_admin_page.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/pages/session_form_page.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _studio = AppUser(uid: 'studio', email: 'studio@example.com', displayName: 'Brooke');

void main() {
  final pages = <(String, Widget)>[
    ('Admin', const AdminPage()),
    ('Session', const AdminSessionPage(sessionId: 's1')),
    ('Add a session', const SessionFormPage()),
    ('Edit session', SessionFormPage(session: testSession('s1'))),
    ('Home page photos', const HomePhotosAdminPage()),
  ];

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    AppUser? user = _studio,
    bool admin = true,
    Brightness brightness = Brightness.light,
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(
      auth: FakeAuthService(signedInAs: user, admin: admin),
      brightness: brightness,
      home: page,
    ));
    await tester.pumpAndSettle();
  }

  for (final (title, page) in pages) {
    testWidgets('$title: the shared top bar, without the "Admin" link', (tester) async {
      await pumpPage(tester, page);

      final bar = tester.widget<BrookieTopBar>(find.byType(BrookieTopBar));
      expect(bar.title, title);
      expect(bar.showAdminLink, isFalse);
    });

    testWidgets('$title: behind the gate', (tester) async {
      await pumpPage(tester, page, user: testUser, admin: false);

      expect(find.byType(AdminGate), findsOneWidget);
      expect(find.textContaining('isn’t an admin'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      for (final width in [320.0, 390.0, 1440.0]) {
        for (final admin in [true, false]) {
          testWidgets(
              '$title: fits ${width.toInt()}px in ${brightness.name} ${admin ? 'for an admin' : 'signed out'}, '
              'with at most one primary button', (tester) async {
            await pumpPage(tester, page,
                user: admin ? _studio : null, brightness: brightness, size: Size(width, 800));

            expect(tester.takeException(), isNull);
            expect(find.byType(FilledButton).evaluate().length, lessThanOrEqualTo(1));
          });
        }
      }
    }
  }

  group('AdminPage', () {
    // The notice is shared by every admin page, so no test leaves one behind.
    tearDown(AdminPage.clearNotice);

    testWidgets('lives at /admin', (tester) async {
      expect(AdminPage.routeName, '/admin');
    });

    /// The home page, with [pages] pushed over it, in a signed-in admin's app.
    Future<NavigatorState> pumpStack(WidgetTester tester, List<Route<void>> pages) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testApp(auth: FakeAuthService(signedInAs: _studio, admin: true), home: const HomePage()));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      for (final page in pages) {
        navigator.push(page);
        await tester.pumpAndSettle();
      }
      return navigator;
    }

    Route<void> adminRoute() => MaterialPageRoute(
          settings: const RouteSettings(name: AdminPage.routeName),
          builder: (context) => const AdminPage(),
        );

    Route<void> sessionRoute() => MaterialPageRoute(builder: (context) => const AdminSessionPage(sessionId: 's1'));

    testWidgets('open: over the home page, closing anything else', (tester) async {
      await pumpStack(tester, [MaterialPageRoute(builder: (context) => const ProfilePage())]);

      AdminPage.open(tester.element(find.byType(ProfilePage)));
      await tester.pumpAndSettle();

      expect(find.byType(ProfilePage), findsNothing);
      expect(find.byType(AdminPage), findsOneWidget);
      final route = ModalRoute.of(tester.element(find.byType(AdminPage)))!;
      expect(route.settings.name, AdminPage.routeName);
      expect(route.isCurrent, isTrue);

      Navigator.of(tester.element(find.byType(AdminPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('returnWithNotice: back to the admin page, which shows the notice', (tester) async {
      await pumpStack(tester, [adminRoute(), sessionRoute()]);

      const notice = 'Deleted the Harper family’s session.';
      AdminPage.returnWithNotice(tester.element(find.byType(AdminSessionPage)), notice);
      await tester.pumpAndSettle();

      expect(find.byType(AdminSessionPage), findsNothing);
      expect(ModalRoute.of(tester.element(find.byType(AdminPage)))!.isCurrent, isTrue);
      final shown = tester.widget<InlineMessage>(find.byType(InlineMessage));
      expect(shown.message, notice);
      expect(shown.tone, StatusTone.success);
      expect(AdminPage.notice.value, notice);
    });

    testWidgets('returnWithNotice with no admin page below goes home rather than nowhere', (tester) async {
      await pumpStack(tester, [sessionRoute()]);

      AdminPage.returnWithNotice(tester.element(find.byType(AdminSessionPage)), 'Deleted.');
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(AdminSessionPage), findsNothing);
    });

    testWidgets('the notice is for one visit: closing the page or opening it again clears it', (tester) async {
      final navigator = await pumpStack(tester, [adminRoute(), sessionRoute()]);
      AdminPage.returnWithNotice(tester.element(find.byType(AdminSessionPage)), 'Saved.');
      await tester.pumpAndSettle();
      expect(find.text('Saved.'), findsOneWidget);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(AdminPage.notice.value, isNull);

      AdminPage.returnWithNotice(tester.element(find.byType(HomePage)), 'Saved again.');
      AdminPage.open(tester.element(find.byType(HomePage)));
      await tester.pumpAndSettle();
      expect(find.byType(InlineMessage), findsNothing);
    });

    testWidgets('clearNotice hides it', (tester) async {
      await pumpStack(tester, [adminRoute(), sessionRoute()]);
      AdminPage.returnWithNotice(tester.element(find.byType(AdminSessionPage)), 'Saved.');
      await tester.pumpAndSettle();

      AdminPage.clearNotice();
      await tester.pump();

      expect(find.byType(InlineMessage), findsNothing);
    });
  });
}
