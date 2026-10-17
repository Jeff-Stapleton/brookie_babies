import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Dates far from today, so the tests don't depend on the clock.
const _future = '2999-03-04';
const _past = '2001-05-06';

Booking _booking(String id, {
  String date = _past,
  String? time,
  String? location,
  String status = 'paid',
  bool photosReady = true,
  String packageName = 'Premium',
}) {
  return Booking.fromMap(id, {
    'packageName': packageName,
    'date': date,
    'time': time,
    'location': location,
    'status': status,
    'photosReady': photosReady,
  })!;
}

/// The [StatusTag] labelled [label].
StatusTag _tag(WidgetTester tester, String label) =>
    tester.widget<StatusTag>(find.widgetWithText(StatusTag, label));

void main() {
  late FakeGalleryService gallery;
  late FakeUrlOpener urlOpener;

  Future<FakeAuthService> pumpProfile(
    WidgetTester tester, {
    bool signedIn = true,
    AppUser user = testUser,
    FakeBookingService? bookings,
    Brightness brightness = Brightness.light,
    Size? size,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final auth = FakeAuthService(signedInAs: signedIn ? user : null);
    await tester.pumpWidget(testApp(
      auth: auth,
      bookings: bookings ?? FakeBookingService(),
      gallery: gallery,
      urlOpener: urlOpener,
      brightness: brightness,
      home: const ProfilePage(),
    ));
    await tester.pumpAndSettle();
    return auth;
  }

  setUp(() {
    gallery = FakeGalleryService();
    urlOpener = FakeUrlOpener();
  });

  testWidgets('signed out: asks the visitor to sign in', (tester) async {
    await pumpProfile(tester, signedIn: false);

    // The top bar's title and the page's headline.
    expect(find.text('Your sessions'), findsNWidgets(2));
    expect(find.text('Sign in to see your sessions and download your photos.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInDialog), findsOneWidget);
  });

  testWidgets("shows the user's account and loads their bookings", (tester) async {
    final bookings = FakeBookingService();
    await pumpProfile(tester, bookings: bookings);

    expect(find.text('Pat Parent'), findsOneWidget);
    expect(find.text('parent@example.com'), findsOneWidget);
    expect(bookings.watchedUids, [testUser.uid]);
    expect(find.textContaining('No sessions to show yet.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'See packages'), findsOneWidget);
  });

  testWidgets('a long name and email fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpProfile(
      tester,
      user: const AppUser(
        uid: 'u2',
        email: 'a.very.long.address.for.a.family@example.com',
        displayName: 'Alexandra Montgomery-Fitzwilliam',
      ),
      bookings: FakeBookingService([
        _booking('b1', status: 'pending', packageName: 'Ultimate', location: '1234 Long Street Name, Salt Lake City'),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Payment pending'), findsOneWidget);
  });

  testWidgets('Sign out returns to the signed-out view', (tester) async {
    final auth = await pumpProfile(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(auth.currentUser, isNull);
    expect(find.text('Sign in to see your sessions and download your photos.'), findsOneWidget);
  });

  testWidgets('splits upcoming and past sessions, nearest first', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([
      _booking('old', date: '1999-01-01', packageName: 'Basic'),
      _booking('later', date: '2999-12-31', packageName: 'Ultimate'),
      _booking('recent', date: _past, packageName: 'Premium'),
      _booking('soon', date: _future, packageName: 'Basic'),
    ]));

    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((text) => text == 'Upcoming' || text == 'Past' || (text?.endsWith(' session') ?? false))
        .toList();
    expect(titles, [
      'Upcoming', 'Basic session', 'Ultimate session',
      'Past', 'Premium session', 'Basic session',
    ]);
  });

  testWidgets('upcoming sessions without photos show neither download nor editing note', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([_booking('soon', date: _future, photosReady: false)]));

    expect(find.text('Download all photos'), findsNothing);
    expect(find.textContaining('Your photos are being edited'), findsNothing);
  });

  testWidgets('an upcoming session whose photos are ready can be downloaded', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([_booking('soon', date: _future)]));

    expect(find.text('Download all photos'), findsOneWidget);
  });

  testWidgets('says when some bookings could not be shown', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([_booking('b1')], 1));

    expect(
      find.text('Some of your sessions couldn’t be shown. Let Brooke know and we’ll sort it out.'),
      findsOneWidget,
    );
    expect(find.byType(InlineMessage), findsOneWidget);
    expect(find.text('Premium session'), findsOneWidget);
  });

  testWidgets('only unreadable bookings: no "No sessions" message', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService(const [], 1));

    expect(find.textContaining('Some of your sessions couldn’t be shown'), findsOneWidget);
    expect(find.textContaining('No sessions to show yet.'), findsNothing);
  });

  testWidgets('past session: downloads the zip in the same tab', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([_booking('b1')]));

    await tester.tap(find.text('Download all photos'));
    await tester.pump();
    expect(gallery.requested, ['b1']);
    expect(find.text('Preparing your photos…'), findsOneWidget);

    final zip = Uri.parse('https://storage.googleapis.com/bucket/gallery-zips/b1.zip?X-Goog-Signature=abc');
    gallery.complete(GalleryDownload(url: zip, photoCount: 42));
    await tester.pumpAndSettle();

    expect(urlOpener.opened.single.url, zip);
    expect(urlOpener.opened.single.windowName, '_self');
    expect(find.text('Download all photos'), findsOneWidget);
  });

  testWidgets('past session: shows why a download failed', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([_booking('b1')]));

    await tester.tap(find.text('Download all photos'));
    await tester.pump();
    gallery.fail(const GalleryException('Your photos aren’t ready yet.'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InlineMessage, 'Your photos aren’t ready yet.'), findsOneWidget);
    expect(urlOpener.opened, isEmpty);
  });

  testWidgets('paid sessions are tagged "Paid"; ready photos say so', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([_booking('b1')]));

    expect(_tag(tester, 'Paid').tone, StatusTone.success);
    expect(_tag(tester, 'Paid').icon, Icons.check);
    expect(_tag(tester, 'Ready to download').tone, StatusTone.success);
    expect(find.widgetWithIcon(FilledButton, Icons.download_outlined), findsOneWidget);
  });

  testWidgets('past session without photos yet: explains they are being edited', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([_booking('b1', photosReady: false)]));

    expect(find.text('Download all photos'), findsNothing);
    expect(find.textContaining('Your photos are being edited'), findsOneWidget);
  });

  testWidgets('cancelled and pending sessions are labelled and have no download', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([
      _booking('c', status: 'cancelled'),
      _booking('p', date: _future, status: 'pending'),
    ]));

    expect(_tag(tester, 'Cancelled').tone, StatusTone.neutral);
    expect(_tag(tester, 'Payment pending').tone, StatusTone.neutral);
    expect(find.text('Paid'), findsNothing);
    expect(find.text('Download all photos'), findsNothing);
  });

  testWidgets('refunded sessions are labelled', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([_booking('r', status: 'refunded')]));

    expect(_tag(tester, 'Refunded').tone, StatusTone.neutral);
    expect(find.text('Download all photos'), findsNothing);
  });

  testWidgets('shows the date, start time and place', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([
      _booking('b1', date: '2001-05-06', time: '14:30', location: 'Liberty Park'),
    ]));

    expect(find.text('Sun, May 6, 2001'), findsOneWidget);
    expect(find.text('2:30 pm'), findsOneWidget);
    expect(find.text('Liberty Park'), findsOneWidget);
    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    expect(find.byIcon(Icons.place_outlined), findsOneWidget);
  });

  testWidgets('times are lowercase with no leading zero', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([
      _booking('morning', time: '09:05'),
      _booking('noon', time: '12:00'),
      _booking('midnight', time: '00:30'),
      _booking('evening', time: '23:45'),
    ]));

    expect(find.text('9:05 am'), findsOneWidget);
    expect(find.text('12:00 pm'), findsOneWidget);
    expect(find.text('12:30 am'), findsOneWidget);
    expect(find.text('11:45 pm'), findsOneWidget);
  });

  testWidgets('dates this year leave out the year', (tester) async {
    final year = DateTime.now().year;
    await pumpProfile(tester, bookings: FakeBookingService([_booking('b1', date: '$year-12-31')]));

    expect(find.textContaining(RegExp(r'^[A-Z][a-z]{2}, Dec 31$')), findsOneWidget);
  });

  testWidgets('says so when bookings fail to load', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService()..error = Exception('permission-denied'));

    expect(
      find.widgetWithText(InlineMessage, 'We couldn’t load your sessions. Refresh the page to try again.'),
      findsOneWidget,
    );
  });

  testWidgets('renders in Darkroom', (tester) async {
    await pumpProfile(
      tester,
      brightness: Brightness.dark,
      bookings: FakeBookingService([_booking('b1'), _booking('b2', date: _future, status: 'pending')]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Paid'), findsOneWidget);
  });

  /// The page's own headline, not the top bar's title.
  Finder headline() => find.descendant(of: find.byType(SingleChildScrollView), matching: find.text('Your sessions'));

  bool hasFocus(WidgetTester tester, Finder finder) => Focus.of(tester.element(finder)).hasPrimaryFocus;

  testWidgets('the top bar is the shared one, and its menu leaves out "Your sessions"', (tester) async {
    await pumpProfile(tester);

    expect(tester.widget<BrookieTopBar>(find.byType(BrookieTopBar)).showSessionsLink, isFalse);
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();

    expect(find.byType(MenuItemButton), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Sign out'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Your sessions'), findsNothing);
  });

  testWidgets('signed out, the top bar has the sign-in chip', (tester) async {
    await pumpProfile(tester, signedIn: false);

    expect(find.descendant(of: find.byType(BrookieTopBar), matching: find.text('Sign in')), findsOneWidget);
  });

  for (final (size, top) in [(const Size(1440, 900), BrookieSpace.s7), (const Size(390, 844), BrookieSpace.s6)]) {
    testWidgets('framed like Booking at ${size.width.toInt()}px: the content column, s${top ~/ 8 + 3} from the bar',
        (tester) async {
      await pumpProfile(tester, size: size, bookings: FakeBookingService([_booking('b1')]));

      final gutter = size.width >= BrookieBreakpoint.gutter ? BrookieSpace.s5 : BrookieSpace.s4;
      final left = size.width >= BrookieSize.contentWidth + 2 * gutter
          ? (size.width - BrookieSize.contentWidth) / 2
          : gutter;
      expect(tester.getTopLeft(headline()), Offset(left, 64 + top));
      expect(tester.widget<Text>(headline()).style, Theme.of(tester.element(headline())).textTheme.headlineLarge);
    });
  }

  testWidgets('on a wide screen, the sessions keep to a 720px column at the left', (tester) async {
    await pumpProfile(tester, size: const Size(1440, 900), bookings: FakeBookingService([_booking('b1')]));

    final left = tester.getTopLeft(headline()).dx;
    expect(tester.getTopRight(find.widgetWithText(OutlinedButton, 'Sign out')).dx, left + 720);
    expect(tester.getTopLeft(find.byType(Card)).dx, left);
    expect(tester.getSize(find.byType(Card)).width, 720);
  });

  testWidgets('signed out on a wide screen: the same frame, the sentence s3 under the headline', (tester) async {
    await pumpProfile(tester, signedIn: false, size: const Size(1440, 900));

    expect(tester.getTopLeft(headline()), const Offset(160, 64 + BrookieSpace.s7));
    final sentence = find.text('Sign in to see your sessions and download your photos.');
    expect(tester.getTopLeft(sentence).dy - tester.getBottomLeft(headline()).dy, BrookieSpace.s3);
    final style = tester.widget<Text>(sentence).style!;
    expect(style.fontFamily, BrookieType.body.fontFamily);
    expect(style.fontSize, BrookieType.body.fontSize);
    expect(style.color, BrookieColors.light.ink);
  });

  testWidgets('the empty state keeps its sentence to the reading width', (tester) async {
    await pumpProfile(tester, size: const Size(1440, 900));

    expect(tester.getSize(find.textContaining('No sessions to show yet.')).width,
        lessThanOrEqualTo(BrookieSize.readingWidth));
  });

  testWidgets('"See packages" goes back home and shows the packages', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(
      auth: FakeAuthService(signedInAs: testUser),
      bookings: FakeBookingService(),
      home: const HomePage(),
    ));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(HomePage)))
        .push(MaterialPageRoute<void>(builder: (context) => const ProfilePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'See packages'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfilePage), findsNothing);
    expect(find.text('Choose your package').hitTestable(), findsOneWidget);
  });

  testWidgets('keyboard: "Download all photos" keeps focus while the photos are prepared', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([_booking('b1')]));
    // Account menu, "Sign out", then the download.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await tester.pump();
    expect(hasFocus(tester, find.text('Download all photos')), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(gallery.requested, ['b1']);
    final busy = find.widgetWithText(FilledButton, 'Preparing your photos…');
    expect(hasFocus(tester, find.text('Preparing your photos…')), isTrue);
    expect(hasFocus(tester, find.text('Sign out')), isFalse);
    expect(tester.widget<FilledButton>(busy).onPressed, isNotNull);
    expect(find.descendant(of: busy, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    // It looks unavailable while it works.
    expect(tester.widget<Material>(find.descendant(of: busy, matching: find.byType(Material))).color,
        BrookieColors.light.surfaceSunk);

    // A second Enter waits for the same download rather than starting another.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(gallery.requested, ['b1']);

    gallery.complete(GalleryDownload(url: Uri.parse('https://example.com/b1.zip'), photoCount: 3));
    await tester.pumpAndSettle();
    expect(hasFocus(tester, find.text('Download all photos')), isTrue);
    expect(urlOpener.opened, hasLength(1));
  });

  testWidgets('screen readers hear "Preparing your photos…"', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpProfile(tester, bookings: FakeBookingService([_booking('b1')]));

    await tester.tap(find.text('Download all photos'));
    await tester.pump();

    expect(
      tester.getSemantics(find.widgetWithText(FilledButton, 'Preparing your photos…')),
      isSemantics(label: 'Preparing your photos…', isButton: true, isEnabled: true, isLiveRegion: true),
    );
    gallery.complete(GalleryDownload(url: Uri.parse('https://example.com/b1.zip'), photoCount: 3));
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('one primary button: the newest ready session; the others are outlined', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([
      _booking('older', date: '1999-01-01', packageName: 'Basic'),
      _booking('newest', date: _past, packageName: 'Ultimate'),
      _booking('editing', date: '2000-01-01', photosReady: false),
    ]));

    final primary = find.widgetWithText(FilledButton, 'Download all photos');
    expect(primary, findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Download all photos'), findsOneWidget);
    expect(find.ancestor(of: primary, matching: find.widgetWithText(Card, 'Ultimate session')), findsOneWidget);
  });

  testWidgets('a busy outlined download keeps its focus ring', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([
      _booking('older', date: '1999-01-01', packageName: 'Basic'),
      _booking('newest', date: _past, packageName: 'Ultimate'),
    ]));
    final outlined = find.widgetWithText(OutlinedButton, 'Download all photos');
    await tester.ensureVisible(outlined);
    await tester.pumpAndSettle();
    await tester.tap(outlined);
    await tester.pump();
    Focus.of(tester.element(find.text('Preparing your photos…'))).requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.shift); // keyboard highlight mode
    await tester.pump();

    final busy = find.widgetWithText(OutlinedButton, 'Preparing your photos…');
    final side = (tester.widget<Material>(find.descendant(of: busy, matching: find.byType(Material))).shape!
            as OutlinedBorder)
        .side;
    expect(side, brookieFocusSide(BrookieColors.light.focus));
    gallery.complete(GalleryDownload(url: Uri.parse('https://example.com/b1.zip'), photoCount: 3));
    await tester.pumpAndSettle();
  });
}
