import 'package:brookie_babies/components/featured_photos.dart';
import 'package:brookie_babies/components/home_hero.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/widgets/network_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  List<Uri> photos(int count) => [
        for (var i = 1; i <= count; i++) Uri.parse('https://photos.example.com/$i.jpg'),
      ];

  Future<void> pumpHome(
    WidgetTester tester, {
    FakePortfolioService? portfolio,
    Size size = const Size(1440, 900),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(testApp(
      auth: FakeAuthService(),
      portfolio: portfolio ?? FakePortfolioService(photos(9)),
      brightness: brightness,
      home: const HomePage(),
    ));
    // The portfolio listing, then the (failing, in tests) photo downloads.
    await tester.pumpAndSettle();
  }

  Finder bookButton() => find.widgetWithText(FilledButton, 'Book a session');

  testWidgets('hero: the first photo with the logo and "Book a session"', (tester) async {
    await pumpHome(tester);

    final hero = find.byType(HomeHero);
    expect(tester.getSize(hero), const Size(1440, 900));
    expect(tester.getSemantics(hero), isSemantics(label: 'Brooke Stapleton Photography'));
    expect(
      tester.widget<NetworkPhoto>(find.descendant(of: hero, matching: find.byType(NetworkPhoto))).url,
      photos(9).first,
    );
    expect(find.descendant(of: hero, matching: find.image(const AssetImage('assets/logo.png'))), findsOneWidget);
    expect(bookButton(), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('"Book a session" scrolls to the packages', (tester) async {
    await pumpHome(tester);
    expect(find.text('Choose your package').hitTestable(), findsNothing);

    await tester.tap(bookButton());
    await tester.pumpAndSettle();

    // The section's 64px gap is left above its title.
    expect(tester.getTopLeft(find.text('Choose your package')).dy, moreOrLessEquals(64, epsilon: 1));
    expect(find.text('Choose Basic').hitTestable(), findsOneWidget);
  });

  testWidgets('with reduced motion, "Book a session" jumps straight there', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpHome(tester);

    await tester.tap(bookButton());
    await tester.pump();

    expect(tester.getTopLeft(find.text('Choose your package')).dy, moreOrLessEquals(64, epsilon: 1));
  });

  testWidgets('introduction: one display line and a lede, no placeholder text', (tester) async {
    await pumpHome(tester);

    expect(find.text('Little ones, while they’re little'), findsOneWidget);
    expect(
      find.text('Calm, unhurried sessions for newborns, babies and the people who hold them.'),
      findsOneWidget,
    );
    expect(find.textContaining('Lorem'), findsNothing);
    expect(find.textContaining('CHOOSE'), findsNothing);
  });

  testWidgets('features up to six photos after the hero, in full rows', (tester) async {
    await pumpHome(tester);
    final featured = find.descendant(of: find.byType(FeaturedPhotos), matching: find.byType(NetworkPhoto));
    expect(
      [for (var i = 0; i < 6; i++) tester.widget<NetworkPhoto>(featured.at(i)).url],
      photos(9).sublist(1, 7),
    );
    expect(featured, findsNWidgets(6));
  });

  testWidgets('drops a lone photo from the last row: three columns on desktop', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService(photos(5)));

    final featured = find.descendant(of: find.byType(FeaturedPhotos), matching: find.byType(NetworkPhoto));
    expect(featured, findsNWidgets(3));
    final first = tester.getRect(featured.at(0));
    expect(first.width / first.height, moreOrLessEquals(4 / 5, epsilon: 0.01));
  });

  testWidgets('drops a lone photo from the last row: two columns on phones', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService(photos(6)), size: const Size(390, 844));

    final featured = find.descendant(of: find.byType(FeaturedPhotos), matching: find.byType(NetworkPhoto));
    expect(featured, findsNWidgets(4));
    expect(tester.getTopLeft(featured.at(0)).dy, tester.getTopLeft(featured.at(1)).dy);
    expect(tester.getTopLeft(featured.at(2)).dy, greaterThan(tester.getBottomLeft(featured.at(0)).dy));
  });

  testWidgets('two featured photos make a pair on desktop', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService(photos(3)));

    final featured = find.descendant(of: find.byType(FeaturedPhotos), matching: find.byType(NetworkPhoto));
    expect(featured, findsNWidgets(2));
    expect(tester.getTopLeft(featured.at(0)).dy, tester.getTopLeft(featured.at(1)).dy);
  });

  testWidgets('a single featured photo is left out rather than shown column-wide', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService(photos(2)));

    expect(find.descendant(of: find.byType(FeaturedPhotos), matching: find.byType(NetworkPhoto)), findsNothing);
    expect(find.byType(NetworkPhoto), findsOneWidget); // the hero
  });

  testWidgets('the butter button is for the photograph; it gives way if the photo fails', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(
      auth: FakeAuthService(),
      portfolio: FakePortfolioService(photos(1)),
      home: const HomePage(),
    ));

    // Still loading: the photograph is expected.
    expect(tester.widget<FilledButton>(bookButton()).style?.backgroundColor?.resolve({}), isNotNull);

    // Photo downloads fail in tests, so the hero falls back to the primary button.
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(bookButton()).style, isNull);
  });

  testWidgets('without photos the hero keeps the logo and the button', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService());

    expect(find.byType(NetworkPhoto), findsNothing);
    expect(find.descendant(of: find.byType(HomeHero), matching: find.image(const AssetImage('assets/logo.png'))),
        findsOneWidget);
    // The primary button, since butter is only for photographs.
    expect(tester.widget<FilledButton>(bookButton()).style, isNull);
  });

  testWidgets('a portfolio error is treated like having no photos', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService(photos(3))..error = Exception('offline'));

    expect(find.byType(NetworkPhoto), findsNothing);
    expect(bookButton(), findsOneWidget);
    expect(find.text('Choose your package'), findsOneWidget);
  });

  testWidgets('footer: the studio and this year, without placeholders', (tester) async {
    await pumpHome(tester);

    expect(find.text('© ${DateTime.now().year} Brooke Stapleton Photography'), findsOneWidget);
    expect(find.textContaining('Your Company'), findsNothing);
    expect(find.textContaining('All rights reserved'), findsNothing);
    for (final icon in [Icons.facebook, Icons.camera_alt, Icons.music_note, Icons.work]) {
      expect(find.byIcon(icon), findsNothing);
    }
  });

  for (final brightness in Brightness.values) {
    for (final size in const [Size(360, 640), Size(390, 844), Size(844, 390), Size(768, 1024), Size(1440, 900)]) {
      testWidgets('lays out without overflow: ${brightness.name}, ${size.width.round()}x${size.height.round()}',
          (tester) async {
        await pumpHome(tester, size: size, brightness: brightness);

        await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -20000));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Brooke Stapleton Photography').hitTestable(), findsWidgets);
      });
    }
  }
}
