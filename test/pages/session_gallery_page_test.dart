import 'package:brookie_babies/pages/session_gallery_page.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/network_photo.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeGalleryService gallery;

  final booking = testSession(
    'fall-family',
    name: 'The Harper family',
    date: DateTime(2026, 10, 24),
    photosReady: true,
  );
  final galleryPhotos = [
    for (var i = 1; i <= 5; i++)
      GalleryPhoto(
        name: 'IMG_$i.jpg',
        url: Uri.parse('https://storage.example/galleries/fall-family/IMG_$i.jpg?signature=$i'),
      ),
  ];

  Future<void> pumpGallery(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        auth: FakeAuthService(signedInAs: testUser),
        gallery: gallery,
        brightness: brightness,
        home: SessionGalleryPage(booking: booking),
      ),
    );
    if (gallery.holdGalleryPhotos) {
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> scrollToPhotos(WidgetTester tester) async {
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    gallery = FakeGalleryService()..galleryPhotos = galleryPhotos;
  });

  test('the date label is a keepsake date with its year', () {
    expect(galleryDateLabel(DateTime(2026, 10, 24)), 'Saturday, October 24, 2026');
  });

  testWidgets('loads the private gallery, with a full first-screen cover and caption', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpGallery(tester);

    expect(gallery.photoRequests, ['fall-family']);
    expect(gallery.adminPreviewRequests, isEmpty);
    expect(find.byType(BrookieTopBar), findsOneWidget);
    expect(find.text('Photo gallery'), findsOneWidget);
    expect(find.text('The Harper family'), findsOneWidget);
    expect(find.text('Saturday, October 24, 2026'), findsOneWidget);
    // The cover and five lazy grid prints (some may be outside the cache
    // extent, so only assert the cover is present here).
    expect(find.byType(NetworkPhoto), findsWidgets);
    expect(find.bySemanticsLabel('Cover photo from The Harper family'), findsOneWidget);

    final cover = find.byType(NetworkPhoto).first;
    final title = find.text('The Harper family');
    expect(tester.getTopLeft(cover).dy, 64);
    expect(tester.getBottomLeft(cover).dy, lessThan(tester.getTopLeft(title).dy));
    expect(tester.getBottomLeft(title).dy, lessThan(844));

    await scrollToPhotos(tester);
    expect(find.text('Your photos'), findsOneWidget);
    expect(find.text('5 photographs'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('shows two columns on a phone and opens every print as a button', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpGallery(tester);
    await scrollToPhotos(tester);

    final first = find.bySemanticsLabel('View photo 1 of 5');
    final second = find.bySemanticsLabel('View photo 2 of 5');

    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    final firstRect = tester.getRect(first);
    final secondRect = tester.getRect(second);
    expect(firstRect.left, 16);
    expect(secondRect.left, firstRect.right + BrookieSpace.s4);
    expect(firstRect.width, secondRect.width);
    expect(firstRect.width / firstRect.height, closeTo(4 / 5, 0.01));
    semantics.dispose();
  });

  testWidgets('a print opens a full-screen viewer with buttons and arrow keys', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpGallery(tester);
    await scrollToPhotos(tester);
    final second = find.bySemanticsLabel('View photo 2 of 5');

    await tester.tap(second);
    await tester.pump();
    await tester.pump(kBrookieFadeDuration);

    expect(find.byTooltip('Close photo'), findsOneWidget);
    expect(find.byTooltip('Previous photo'), findsOneWidget);
    expect(find.byTooltip('Next photo'), findsOneWidget);
    expect(find.text('2 of 5'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Photo 2 of 5 from The Harper family')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('3 of 5'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Photo 3 of 5 from The Harper family')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Previous photo'));
    await tester.pump();
    expect(find.text('2 of 5'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close photo'), findsNothing);
    semantics.dispose();
  });

  testWidgets('the viewer disables previous and next at the ends', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpGallery(tester);
    await scrollToPhotos(tester);
    final first = find.bySemanticsLabel('View photo 1 of 5');
    await tester.tap(first);
    await tester.pump();
    await tester.pump(kBrookieFadeDuration);

    Finder button(String tooltip) => find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        );
    expect(tester.widget<IconButton>(button('Previous photo')).onPressed, isNull);
    expect(tester.widget<IconButton>(button('Next photo')).onPressed, isNotNull);

    for (var i = 1; i < galleryPhotos.length; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(find.text('5 of 5'), findsOneWidget);
    expect(tester.widget<IconButton>(button('Next photo')).onPressed, isNull);
    semantics.dispose();
  });

  testWidgets('says why loading failed and retries', (tester) async {
    gallery.galleryPhotosError = const GalleryException('Your photos aren’t ready yet.');
    await pumpGallery(tester);

    expect(find.widgetWithText(InlineMessage, 'Your photos aren’t ready yet.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    expect(find.byType(NetworkPhoto), findsNothing);

    gallery.galleryPhotosError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(gallery.photoRequests, ['fall-family', 'fall-family']);
    await scrollToPhotos(tester);
    expect(find.text('Your photos'), findsOneWidget);
    expect(find.byType(NetworkPhoto), findsWidgets);
  });

  testWidgets('keeps the loading state until the links arrive', (tester) async {
    gallery.holdGalleryPhotos = true;
    await pumpGallery(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('The Harper family'), findsOneWidget);
    expect(find.byType(NetworkPhoto), findsNothing);

    gallery.completePhotos();
    await tester.pumpAndSettle();
    await scrollToPhotos(tester);
    expect(find.text('Your photos'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('a long title fits a 320px phone in ${brightness.name}', (tester) async {
      final longBooking = testSession(
        'long',
        name: 'The Montgomery-Fitzwilliam family — autumn in the mountains',
        date: DateTime(2026, 10, 24),
        photosReady: true,
      );
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(
          auth: FakeAuthService(signedInAs: testUser),
          gallery: gallery,
          brightness: brightness,
          home: SessionGalleryPage(booking: longBooking),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(longBooking.familyTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
