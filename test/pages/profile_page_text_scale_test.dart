// "Your sessions", the account menu and the sign-in dialog at twice the text
// size on small phones, measured with the real fonts (the test font sets
// every glyph a full em wide, which would overflow where the site doesn't).

import 'package:brookie_babies/components/account_button.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Booking _booking(String id, {
  String date = '2001-05-06',
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

/// Whether some word of [text] is wider than its line, so it must break
/// inside the word.
bool _breaksAWord(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  for (final word in paragraph.text.toPlainText().split(RegExp(r'[\s-]+'))) {
    final painter = TextPainter(
      text: TextSpan(text: word, style: paragraph.text.style),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    final tooWide = painter.width > paragraph.constraints.maxWidth + 0.5;
    painter.dispose();
    if (tooWide) return true;
  }
  return false;
}

void main() {
  setUpAll(() async {
    final jost = FontLoader('Jost');
    for (final weight in ['Light', 'Regular', 'Medium']) {
      jost.addFont(rootBundle.load('assets/fonts/Jost-$weight.ttf'));
    }
    final newsreader = FontLoader('Newsreader')
      ..addFont(rootBundle.load('assets/fonts/Newsreader-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Newsreader-LightItalic.ttf'));
    await Future.wait([jost.load(), newsreader.load()]);
  });

  late FakeGalleryService gallery;

  setUp(() => gallery = FakeGalleryService());

  Future<void> pump(WidgetTester tester, Widget home, {required double width, bool signedIn = true, FakeBookingService? bookings}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(testApp(
      auth: FakeAuthService(signedInAs: signedIn ? testUser : null),
      bookings: bookings ?? FakeBookingService(),
      gallery: gallery,
      home: home,
    ));
    await tester.pumpAndSettle();
  }

  final sample = FakeBookingService([
    _booking('soon', date: '2999-03-04', time: '10:00', location: 'Studio', status: 'pending'),
    _booking('b1', time: '14:30', location: 'Liberty Park'),
    _booking('b2', date: '1999-01-01', time: '09:00'),
    _booking('b3', date: '1998-01-01', photosReady: false),
  ], 1);

  for (final width in [320.0, 360.0]) {
    testWidgets('signed in at ${width.toInt()}px: nothing overflows, preparing or not', (tester) async {
      await pump(tester, const ProfilePage(), width: width, bookings: sample);
      expect(tester.takeException(), isNull);

      final download = find.text('Download all photos').first;
      await tester.ensureVisible(download);
      await tester.pumpAndSettle();
      await tester.tap(download);
      await tester.pump();
      expect(find.text('Preparing your photos…'), findsOneWidget);
      expect(tester.takeException(), isNull);

      gallery.fail(const GalleryException('Your photos aren’t ready yet.'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed out at ${width.toInt()}px: nothing overflows', (tester) async {
      await pump(tester, const ProfilePage(), width: width, signedIn: false);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the empty state at ${width.toInt()}px: nothing overflows', (tester) async {
      await pump(tester, const ProfilePage(), width: width);

      expect(find.textContaining('No sessions yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the headline keeps its words whole at ${width.toInt()}px', (tester) async {
      await pump(tester, const ProfilePage(), width: width, bookings: sample);

      final headline =
          find.descendant(of: find.byType(SingleChildScrollView), matching: find.text('Your sessions'));
      expect(_breaksAWord(tester, headline), isFalse);
      expect(_breaksAWord(tester, find.text('Premium session').first), isFalse);
      expect(_breaksAWord(tester, find.text('Upcoming')), isFalse);
    });

    testWidgets('the account menu at ${width.toInt()}px: nothing overflows', (tester) async {
      await pump(
        tester,
        const Scaffold(body: Align(alignment: Alignment.topRight, child: AccountButton())),
        width: width,
      );
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sign-in chip at ${width.toInt()}px: nothing overflows', (tester) async {
      await pump(
        tester,
        const Scaffold(body: Align(alignment: Alignment.topRight, child: AccountButton(onPhoto: true))),
        width: width,
        signedIn: false,
      );

      expect(tester.takeException(), isNull);
      expect(_breaksAWord(tester, find.text('Sign in')), isFalse);
    });
  }
}
