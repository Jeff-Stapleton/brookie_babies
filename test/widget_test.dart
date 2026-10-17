// Tests for the home page's package section: the cards, choosing a package,
// and the remembered choice.

import 'package:brookie_babies/components/packages.dart';
import 'package:brookie_babies/models/session_package.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/package_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  // Real Jost metrics, so the side-by-side layout is decided on the widths
  // the site actually renders (the test font is much wider).
  setUpAll(() async {
    final jost = FontLoader('Jost');
    for (final weight in ['Light', 'Regular', 'Medium']) {
      jost.addFont(rootBundle.load('assets/fonts/Jost-$weight.ttf'));
    }
    await jost.load();
  });

  Future<void> pumpPackages(
    WidgetTester tester, {
    Size size = const Size(1800, 1200),
    Brightness brightness = Brightness.light,
  }) async {
    // A desktop window by default, where the cards sit side by side.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(testApp(
      auth: FakeAuthService(),
      brightness: brightness,
      home: const Scaffold(body: SingleChildScrollView(child: Packages())),
    ));
  }

  void setTextScale(WidgetTester tester, double scale) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Whether the button labelled [label] has keyboard focus.
  bool hasFocus(WidgetTester tester, String label) => Focus.of(tester.element(find.text(label))).hasPrimaryFocus;

  Future<void> tabTo(WidgetTester tester, String label) async {
    for (var i = 0; i < 6 && !hasFocus(tester, label); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(hasFocus(tester, label), isTrue, reason: 'Tab should reach "$label"');
  }

  Future<void> choose(WidgetTester tester, String buttonLabel) async {
    await tester.ensureVisible(find.text(buttonLabel));
    await tester.tap(find.text(buttonLabel));
    await tester.pumpAndSettle();
  }

  List<Rect> cardRects(WidgetTester tester) => [
        for (var i = 0; i < SessionPackage.all.length; i++) tester.getRect(find.byType(PackageCard).at(i)),
      ];

  Future<void> goBack(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
  }

  testWidgets('shows each package with its price, inclusions and button', (tester) async {
    await pumpPackages(tester);

    expect(find.text('Choose your package'), findsOneWidget);
    for (final package in SessionPackage.all) {
      expect(find.text(package.name), findsOneWidget);
      expect(find.text(package.priceLabel), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Choose ${package.name}'), findsOneWidget);
    }
    final inclusions = [for (final package in SessionPackage.all) ...package.inclusions];
    for (final inclusion in inclusions.toSet()) {
      expect(find.text(inclusion), findsNWidgets(inclusions.where((i) => i == inclusion).length));
    }
    expect(find.text('Selected'), findsNothing);
    expect(find.textContaining('Lorem'), findsNothing);
  });

  testWidgets('one sentence under the headline, in body and ink, s3 below it', (tester) async {
    await pumpPackages(tester);

    const intro = 'After your session, your edited photos arrive in your account, ready to download.';
    final style = tester.widget<Text>(find.text(intro)).style!;
    expect(style.fontFamily, BrookieType.body.fontFamily);
    expect(style.fontSize, BrookieType.body.fontSize);
    expect(style.color, BrookieColors.light.ink);
    expect(
      tester.getTopLeft(find.text(intro)).dy - tester.getBottomLeft(find.text('Choose your package')).dy,
      BrookieSpace.s3,
    );
  });

  for (final width in [1024.0, 1440.0, 1800.0]) {
    testWidgets('cards sit side by side at equal height on a ${width.round()}px window', (tester) async {
      await pumpPackages(tester, size: Size(width, 1200));

      final cards = cardRects(tester);
      expect({for (final card in cards) card.top}, hasLength(1));
      expect({for (final card in cards) card.height}, hasLength(1));
    });
  }

  for (final width in [360.0, 390.0, 600.0, 760.0, 820.0]) {
    testWidgets('cards stack on a ${width.round()}px window', (tester) async {
      await pumpPackages(tester, size: Size(width, 900));

      final cards = cardRects(tester);
      expect({for (final card in cards) card.left}, hasLength(1));
      for (var i = 1; i < cards.length; i++) {
        expect(cards[i].top, greaterThan(cards[i - 1].bottom));
      }
      expect(tester.takeException(), isNull);
    });
  }

  // Phones fill the column; on a tablet the stack keeps a phone's measure at
  // the left of the column, rather than stretching its buttons across it.
  for (final (width, cardWidth) in [(360.0, 328.0), (390.0, 358.0), (600.0, 520.0), (768.0, 520.0), (820.0, 520.0)]) {
    testWidgets('stacked cards are ${cardWidth.round()}px wide on a ${width.round()}px window', (tester) async {
      await pumpPackages(tester, size: Size(width, 900));

      final gutter = width >= BrookieBreakpoint.gutter ? BrookieSpace.s5 : BrookieSpace.s4;
      expect(tester.getTopLeft(find.text('Choose your package')).dx, gutter);
      for (final card in cardRects(tester)) {
        expect(card.left, gutter);
        expect(card.width, cardWidth);
      }
    });
  }

  testWidgets('choosing a package opens scheduling for that package', (tester) async {
    await pumpPackages(tester);

    await choose(tester, 'Choose Premium');

    expect(tester.widget<SchedulingPage>(find.byType(SchedulingPage)).packageName, 'Premium');
  });

  testWidgets('coming back shows the chosen package selected, ready to continue', (tester) async {
    await pumpPackages(tester);

    await choose(tester, 'Choose Premium');
    await goBack(tester);

    expect(find.widgetWithText(FilledButton, 'Continue with Premium'), findsOneWidget);
    expect(find.text('Choose Premium'), findsNothing);
    expect(find.text('Selected'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Choose Basic'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Choose Ultimate'), findsOneWidget);

    final premium = find.widgetWithText(PackageCard, 'Premium');
    expect(tester.widget<PackageCard>(premium).selected, isTrue);
    expect(tester.getSemantics(premium), isSemantics(isSelected: true));
    expect(tester.getSemantics(find.widgetWithText(PackageCard, 'Basic')), isSemantics(isSelected: false));

    await choose(tester, 'Continue with Premium');
    expect(tester.widget<SchedulingPage>(find.byType(SchedulingPage)).packageName, 'Premium');
  });

  testWidgets('choosing another package moves the selection', (tester) async {
    await pumpPackages(tester);

    await choose(tester, 'Choose Premium');
    await goBack(tester);
    await choose(tester, 'Choose Ultimate');

    expect(tester.widget<SchedulingPage>(find.byType(SchedulingPage)).packageName, 'Ultimate');
    await goBack(tester);
    expect(find.widgetWithText(FilledButton, 'Continue with Ultimate'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Choose Premium'), findsOneWidget);
    expect(find.text('Selected'), findsOneWidget);
  });

  testWidgets('coming back by keyboard, focus is on the chosen card, now "Continue with …"', (tester) async {
    await pumpPackages(tester);

    await tabTo(tester, 'Choose Premium');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<SchedulingPage>(find.byType(SchedulingPage)).packageName, 'Premium');

    await goBack(tester);
    expect(hasFocus(tester, 'Continue with Premium'), isTrue);
  });

  for (final brightness in Brightness.values) {
    testWidgets('"Continue with …" shows an on-butter focus ring with a gap (${brightness.name})', (tester) async {
      await pumpPackages(tester, brightness: brightness);
      await choose(tester, 'Choose Premium');
      await goBack(tester);

      final button = find.widgetWithText(FilledButton, 'Continue with Premium');
      final surface = find.descendant(of: button, matching: find.byType(Material));
      final onButter = BrookieColors.light.onButter;
      expect((tester.widget<Material>(surface).shape! as OutlinedBorder).side, BorderSide.none);

      await tabTo(tester, 'Continue with Premium');
      await tester.pumpAndSettle();
      // Not the theme's ink ring, which barely shows on butter in Darkroom.
      expect((tester.widget<Material>(surface).shape! as OutlinedBorder).side, brookieFocusSide(onButter));
    });
  }

  for (final width in [320.0, 360.0]) {
    testWidgets('at 200% text on a ${width.round()}px window, the selected card keeps its name whole',
        (tester) async {
      setTextScale(tester, 2);
      await pumpPackages(tester, size: Size(width, 900));
      await choose(tester, 'Choose Ultimate');
      await goBack(tester);

      // One line of the title style: "Selected" has dropped below the name.
      final name = find.text('Ultimate');
      final title = BrookieType.title;
      expect(tester.getSize(name).height, moreOrLessEquals(2 * title.fontSize! * title.height!, epsilon: 0.5));
      expect(tester.getTopLeft(find.text('Selected')).dy, greaterThan(tester.getBottomLeft(name).dy));

      // The wrapped label keeps clear of the pill's edges.
      const label = 'Continue with Ultimate';
      final button = tester.getRect(find.widgetWithText(FilledButton, label));
      final text = tester.getRect(find.text(label));
      expect(text.top - button.top, greaterThanOrEqualTo(BrookieSpace.s2));
      expect(button.bottom - text.bottom, greaterThanOrEqualTo(BrookieSpace.s2));
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 360.0, 390.0, 768.0, 1024.0, 1440.0]) {
      testWidgets('at 200% text nothing overflows: ${brightness.name}, ${width.round()}px', (tester) async {
        setTextScale(tester, 2);
        await pumpPackages(tester, size: Size(width, 900), brightness: brightness);
        expect(tester.takeException(), isNull);

        await choose(tester, 'Choose Ultimate');
        await goBack(tester);
        expect(find.text('Selected'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('renders in Darkroom', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(testApp(
      auth: FakeAuthService(),
      brightness: Brightness.dark,
      home: const Scaffold(body: SingleChildScrollView(child: Packages())),
    ));

    expect(find.byType(PackageCard), findsNWidgets(SessionPackage.all.length));
    expect(tester.takeException(), isNull);
  });
}
