// Tests for the home page's package section: the cards, choosing a package,
// and the remembered choice.

import 'package:brookie_babies/components/packages.dart';
import 'package:brookie_babies/models/session_package.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
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

  Future<void> pumpPackages(WidgetTester tester, {Size size = const Size(1800, 1200)}) async {
    // The scheduling page's session cards have fixed widths, so default to a
    // desktop-sized window.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(testApp(
      auth: FakeAuthService(),
      home: const Scaffold(body: SingleChildScrollView(child: Packages())),
    ));
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

  for (final width in [1024.0, 1440.0, 1800.0]) {
    testWidgets('cards sit side by side at equal height on a ${width.round()}px window', (tester) async {
      await pumpPackages(tester, size: Size(width, 1200));

      final cards = cardRects(tester);
      expect({for (final card in cards) card.top}, hasLength(1));
      expect({for (final card in cards) card.height}, hasLength(1));
    });
  }

  for (final width in [360.0, 390.0, 600.0, 760.0]) {
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
