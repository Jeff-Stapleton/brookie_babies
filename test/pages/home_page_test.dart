import 'dart:async';

import 'package:brookie_babies/components/featured_photos.dart';
import 'package:brookie_babies/components/home_hero.dart';
import 'package:brookie_babies/components/page_footer.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/brookie_logo.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:brookie_babies/widgets/network_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_photos.dart';
import '../support/fakes.dart';

/// Holds each photoUrls answer until the test gives it: [loads] in order.
class _HeldPortfolio extends FakePortfolioService {
  final loads = <Completer<List<Uri>>>[];

  @override
  Future<List<Uri>> photoUrls({int? limit}) => (loads..add(Completer())).last.future;
}

void main() {
  List<Uri> photos(int count) => [
        for (var i = 1; i <= count; i++) Uri.parse('https://photos.example.com/$i.jpg'),
      ];

  // Photos stay loading unless a test lists them as broken.
  final server = FakePhotoServer();

  void homeTest(String description, Future<void> Function(WidgetTester tester) body) {
    testWidgets(description, (tester) async {
      server.start();
      try {
        await body(tester);
      } finally {
        server.stop();
        server.broken.clear();
      }
    });
  }

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
    // The portfolio listing, then any broken photos failing.
    await tester.pumpAndSettle();
  }

  Finder bookButton() => find.widgetWithText(FilledButton, 'Book a session');
  Finder featured() => find.descendant(of: find.byType(FeaturedPhotos), matching: find.byType(NetworkPhoto));
  Finder heroPhoto() => find.descendant(of: find.byType(HomeHero), matching: find.byType(NetworkPhoto));
  List<Uri> urls(WidgetTester tester, Finder photos) => [
        for (final photo in tester.widgetList<NetworkPhoto>(photos)) photo.url,
      ];

  homeTest('hero: the first photo with the logo and "Book a session"', (tester) async {
    await pumpHome(tester);

    final hero = find.byType(HomeHero);
    expect(tester.getSize(hero), const Size(1440, 900));
    expect(tester.getSemantics(hero), isSemantics(label: 'Brooke Stapleton Photography'));
    expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9).first);
    expect(find.descendant(of: hero, matching: find.image(const AssetImage('assets/logo.png'))), findsOneWidget);
    expect(bookButton(), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  homeTest('the logo takes its full size before it has loaded, so nothing moves', (tester) async {
    await pumpHome(tester, size: const Size(390, 844));

    for (final logo in tester.widgetList<BrookieLogo>(find.byType(BrookieLogo))) {
      final size = tester.getSize(find.byWidget(logo));
      expect(size.width, logo.width);
      expect(size.height, moreOrLessEquals(logo.width * 453 / 551, epsilon: 0.01));
    }
    expect(find.byType(BrookieLogo), findsNWidgets(2)); // the hero and the footer
  });

  homeTest('"Book a session" scrolls to the packages', (tester) async {
    await pumpHome(tester);
    expect(find.text('Choose your package').hitTestable(), findsNothing);

    await tester.tap(bookButton());
    await tester.pumpAndSettle();

    // The section's 64px gap is left above its title.
    expect(tester.getTopLeft(find.text('Choose your package')).dy, moreOrLessEquals(64, epsilon: 1));
    expect(find.text('Choose Basic').hitTestable(), findsOneWidget);
  });

  homeTest('with reduced motion, "Book a session" jumps straight there', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpHome(tester);

    await tester.tap(bookButton());
    await tester.pump();

    expect(tester.getTopLeft(find.text('Choose your package')).dy, moreOrLessEquals(64, epsilon: 1));
  });

  for (final (size, gap) in const [(Size(1440, 900), 64.0), (Size(390, 844), 48.0)]) {
    homeTest('"See packages" on another page comes back home to the packages (${size.width.round()}px)',
        (tester) async {
      await pumpHome(tester, size: size);
      tester.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          body: Center(
            child: OutlinedButton(
              onPressed: () => HomePage.showPackages(context),
              child: const Text('See packages'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('See packages'));
      await tester.pumpAndSettle();

      expect(find.text('See packages'), findsNothing);
      expect(tester.getTopLeft(find.text('Choose your package')).dy, moreOrLessEquals(gap, epsilon: 1));
      expect(find.text('Choose Basic').hitTestable(), findsOneWidget);
    });
  }

  homeTest('the butter button shows a two-tone focus ring, only while it has keyboard focus', (tester) async {
    await pumpHome(tester);
    final ring = find.ancestor(of: bookButton(), matching: find.byType(FocusRing));
    expect(tester.widget<FocusRing>(ring).visible, isFalse);

    bool bookFocused() => Focus.of(tester.element(find.text('Book a session'))).hasPrimaryFocus;
    for (var i = 0; i < 4 && !bookFocused(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(bookFocused(), isTrue);
    expect(tester.widget<FocusRing>(ring).visible, isTrue);

    // On-butter against the button, then butter, so one band always shows.
    final c = BrookieColors.light;
    final bands = [
      for (final box in tester.widgetList<DecoratedBox>(find.descendant(of: ring, matching: find.byType(DecoratedBox))))
        if (box.decoration case BoxDecoration(border: Border(top: BorderSide(:final color)))) color,
    ];
    expect(bands, [c.onButter, c.butter]);
    // The button draws no ring of its own on top.
    final style = tester.widget<FilledButton>(bookButton()).style!;
    expect(style.side!.resolve({WidgetState.focused}), BorderSide.none);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.widget<FocusRing>(ring).visible, isFalse);
  });

  homeTest('introduction: one display line and a lede, no placeholder text', (tester) async {
    await pumpHome(tester);

    const display = 'Little ones, while they’re little';
    expect(find.text(display), findsOneWidget);
    expect(tester.widget<Text>(find.text(display)).style?.fontSize, BrookieType.display.fontSize);
    expect(
      find.text('Calm, unhurried sessions for newborns, babies and the people who hold them.'),
      findsOneWidget,
    );
    expect(find.textContaining('Lorem'), findsNothing);
    expect(find.textContaining('CHOOSE'), findsNothing);
  });

  homeTest('introduction: the display line takes its compact size on phones', (tester) async {
    await pumpHome(tester, size: const Size(390, 844));

    final style = tester.widget<Text>(find.text('Little ones, while they’re little')).style!;
    expect(style.fontSize, BrookieType.displayCompact.fontSize);
    expect(style.height, BrookieType.displayCompact.height);
    expect(style.color, BrookieColors.light.ink);
  });

  homeTest('asks for no more photos than it shows', (tester) async {
    final portfolio = FakePortfolioService(photos(9));
    await pumpHome(tester, portfolio: portfolio);

    expect(portfolio.requestedLimit, 1 + FeaturedPhotos.maxCount);
  });

  homeTest('features up to six photos after the hero, in full rows', (tester) async {
    await pumpHome(tester);

    expect(urls(tester, featured()), photos(9).sublist(1, 7));
  });

  homeTest('featured photos decode at about their tile size, the hero at full size', (tester) async {
    await pumpHome(tester);

    final tileWidth = tester.getSize(featured().first).width;
    for (final photo in tester.widgetList<NetworkPhoto>(featured())) {
      final decode = photo.decodeSize!;
      expect(decode.width, greaterThanOrEqualTo(tileWidth));
      expect(decode.width, lessThan(tileWidth + 256));
      expect(decode.height, decode.width * 5 / 4);
    }
    expect(tester.widget<NetworkPhoto>(heroPhoto()).decodeSize, isNull);
  });

  homeTest('drops a lone photo from the last row: three columns on desktop', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService(photos(5)));

    expect(featured(), findsNWidgets(3));
    final first = tester.getRect(featured().at(0));
    expect(first.width / first.height, moreOrLessEquals(4 / 5, epsilon: 0.01));
  });

  homeTest('drops a lone photo from the last row: two columns on phones', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService(photos(6)), size: const Size(390, 844));

    expect(featured(), findsNWidgets(4));
    expect(tester.getTopLeft(featured().at(0)).dy, tester.getTopLeft(featured().at(1)).dy);
    expect(tester.getTopLeft(featured().at(2)).dy, greaterThan(tester.getBottomLeft(featured().at(0)).dy));
  });

  homeTest('two featured photos make a pair on desktop', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService(photos(3)));

    expect(featured(), findsNWidgets(2));
    expect(tester.getTopLeft(featured().at(0)).dy, tester.getTopLeft(featured().at(1)).dy);
  });

  homeTest('a single featured photo is left out rather than shown column-wide', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService(photos(2)));

    expect(featured(), findsNothing);
    expect(find.byType(NetworkPhoto), findsOneWidget); // the hero
  });

  homeTest('if the hero photo can’t be loaded, the next one takes its place', (tester) async {
    server.broken.add(photos(9).first);
    await pumpHome(tester);

    expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9)[1]);
    // Still on a photograph: the butter button.
    expect(tester.widget<FilledButton>(bookButton()).style, isNotNull);
    // The featured photos start after the new hero; five make one row of three.
    expect(urls(tester, featured()), photos(9).sublist(2, 5));
  });

  homeTest('a featured photo that can’t be loaded is left out, and the grid closes up', (tester) async {
    server.broken.add(photos(9)[2]);
    await pumpHome(tester, size: const Size(390, 844));

    expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9).first);
    expect(urls(tester, featured()), [photos(9)[1], photos(9)[3], photos(9)[4], photos(9)[5]]);
  });

  group('reloadPhotos', () {
    homeTest('shows the photos as they are now', (tester) async {
      // The fake hands back this list, so changing it changes the photos.
      final shown = photos(9);
      final portfolio = FakePortfolioService(shown);
      await pumpHome(tester, portfolio: portfolio);
      expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9).first);

      shown.setAll(0, photos(9).reversed);
      HomePage.reloadPhotos();
      await tester.pumpAndSettle();

      expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9).last);
      expect(urls(tester, featured()), photos(9).reversed.toList().sublist(1, 7));
      expect(portfolio.requestedLimit, 1 + FeaturedPhotos.maxCount);
    });

    homeTest('gives photos that couldn’t be loaded another try', (tester) async {
      server.broken.add(photos(9).first);
      await pumpHome(tester);
      expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9)[1]);

      server.broken.clear();
      HomePage.reloadPhotos();
      await tester.pumpAndSettle();

      expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9).first);
      expect(urls(tester, featured()), photos(9).sublist(1, 7));
    });

    homeTest('keeps the photos shown if the new list can’t be had', (tester) async {
      final portfolio = FakePortfolioService(photos(9));
      await pumpHome(tester, portfolio: portfolio);

      portfolio.error = Exception('offline');
      HomePage.reloadPhotos();
      await tester.pumpAndSettle();

      expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9).first);
      expect(featured(), findsNWidgets(6));
    });

    homeTest('an older load that answers late doesn’t replace a newer one’s photos', (tester) async {
      final portfolio = _HeldPortfolio();
      await pumpHome(tester, portfolio: portfolio);
      portfolio.loads.single.complete(photos(9));
      await tester.pumpAndSettle();

      HomePage.reloadPhotos();
      HomePage.reloadPhotos();
      portfolio.loads.last.complete(photos(9).reversed.toList());
      await tester.pumpAndSettle();
      portfolio.loads[1].complete(photos(3));
      await tester.pumpAndSettle();

      expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9).last);
    });

    homeTest('a newer load that fails doesn’t throw away an older one that works', (tester) async {
      final portfolio = _HeldPortfolio();
      await pumpHome(tester, portfolio: portfolio);
      portfolio.loads.single.complete(photos(9));
      await tester.pumpAndSettle();

      HomePage.reloadPhotos();
      HomePage.reloadPhotos();
      portfolio.loads.last.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      portfolio.loads[1].complete(photos(9).reversed.toList());
      await tester.pumpAndSettle();

      expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9).last);
    });

    homeTest('a reload that fails during the first load waits for it', (tester) async {
      final portfolio = _HeldPortfolio();
      await pumpHome(tester, portfolio: portfolio);

      HomePage.reloadPhotos();
      portfolio.loads.last.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      // Still loading, not "no photos".
      expect(tester.widget<HomeHero>(find.byType(HomeHero)).loading, isTrue);
      portfolio.loads.first.complete(photos(9));
      await tester.pumpAndSettle();

      expect(tester.widget<NetworkPhoto>(heroPhoto()).url, photos(9).first);
    });

    homeTest('a home page that has closed doesn’t listen any more', (tester) async {
      await pumpHome(tester);
      await tester.pumpWidget(const SizedBox());

      HomePage.reloadPhotos();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  homeTest('the butter button is for the photograph; it gives way if no photo loads', (tester) async {
    server.broken.add(photos(1).single);
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

    // The only photo fails, so the hero falls back to the primary button.
    await tester.pumpAndSettle();
    expect(find.byType(NetworkPhoto), findsNothing);
    expect(tester.widget<FilledButton>(bookButton()).style, isNull);
  });

  homeTest('without photos the hero keeps the logo and the button', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService());

    expect(find.byType(NetworkPhoto), findsNothing);
    expect(find.descendant(of: find.byType(HomeHero), matching: find.image(const AssetImage('assets/logo.png'))),
        findsOneWidget);
    // The primary button, since butter is only for photographs.
    expect(tester.widget<FilledButton>(bookButton()).style, isNull);
  });

  homeTest('a portfolio error is treated like having no photos', (tester) async {
    await pumpHome(tester, portfolio: FakePortfolioService(photos(3))..error = Exception('offline'));

    expect(find.byType(NetworkPhoto), findsNothing);
    expect(bookButton(), findsOneWidget);
    expect(find.text('Choose your package'), findsOneWidget);
  });

  homeTest('footer: the logo and the copyright, without repeating the name or placeholders', (tester) async {
    await pumpHome(tester);

    final footer = find.byType(PageFooter);
    expect(find.descendant(of: footer, matching: find.byType(BrookieLogo)), findsOneWidget);
    expect(
      find.descendant(of: footer, matching: find.byType(Text)),
      findsOneWidget,
      reason: 'the logo already says the name',
    );
    expect(find.text('© ${DateTime.now().year} Brooke Stapleton Photography'), findsOneWidget);
    expect(find.textContaining('Your Company'), findsNothing);
    expect(find.textContaining('All rights reserved'), findsNothing);
    for (final icon in [Icons.facebook, Icons.camera_alt, Icons.music_note, Icons.work]) {
      expect(find.byIcon(icon), findsNothing);
    }
  });

  for (final textScale in const [1.0, 2.0]) {
    for (final brightness in Brightness.values) {
      for (final size in const [
        Size(320, 568),
        Size(360, 640),
        Size(390, 844),
        Size(844, 390),
        Size(768, 1024),
        Size(1440, 900),
      ]) {
        final name = '${brightness.name}, ${size.width.round()}x${size.height.round()}, text ×$textScale';
        homeTest('lays out without overflow: $name', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpHome(tester, size: size, brightness: brightness);
          // The hero on its photograph (still loading), with the butter button.
          expect(tester.widget<FilledButton>(bookButton()).style, isNotNull);
          expect(tester.takeException(), isNull);

          await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -40000));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.textContaining('Brooke Stapleton Photography').hitTestable(), findsWidgets);
        });
      }
    }
  }
}
