import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Dates far from today, so the tests don't depend on the clock.
const _future = '2999-03-04';
const _past = '2001-05-06';

Booking _booking(String id, {
  String date = _past,
  String? time,
  String status = 'paid',
  bool photosReady = true,
  String packageName = 'Premium',
}) {
  return Booking.fromMap(id, {
    'packageName': packageName,
    'date': date,
    'time': time,
    'status': status,
    'photosReady': photosReady,
  })!;
}

void main() {
  late FakeGalleryService gallery;
  late FakeUrlOpener urlOpener;

  Future<FakeAuthService> pumpProfile(
    WidgetTester tester, {
    bool signedIn = true,
    FakeBookingService? bookings,
  }) async {
    final auth = FakeAuthService(signedInAs: signedIn ? testUser : null);
    await tester.pumpWidget(testApp(
      auth: auth,
      bookings: bookings ?? FakeBookingService(),
      gallery: gallery,
      urlOpener: urlOpener,
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

    expect(find.textContaining("Some of your sessions couldn't be shown"), findsOneWidget);
    expect(find.text('Premium session'), findsOneWidget);
  });

  testWidgets('only unreadable bookings: no "No sessions" message', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService(const [], 1));

    expect(find.textContaining("Some of your sessions couldn't be shown"), findsOneWidget);
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
    gallery.fail(const GalleryException("Your photos aren't ready yet."));
    await tester.pumpAndSettle();

    expect(find.text("Your photos aren't ready yet."), findsOneWidget);
    expect(urlOpener.opened, isEmpty);
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

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Payment pending'), findsOneWidget);
    expect(find.text('Download all photos'), findsNothing);
  });

  testWidgets('shows the date and start time', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService([_booking('b1', date: '2001-05-06', time: '14:30')]));

    expect(find.text('Sunday, May 6, 2001'), findsOneWidget);
    expect(find.text('2:30 PM'), findsOneWidget);
  });

  testWidgets('says so when bookings fail to load', (tester) async {
    await pumpProfile(tester, bookings: FakeBookingService()..error = Exception('permission-denied'));

    expect(find.text("We couldn't load your sessions. Please try again later."), findsOneWidget);
  });
}
