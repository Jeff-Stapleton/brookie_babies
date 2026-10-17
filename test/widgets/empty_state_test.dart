// The one "nothing here yet" pattern, on Your sessions and on Book a session,
// measured with the real fonts (the test font sets every glyph a full em
// wide, so no sentence would fit a line).

import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _noSessions = 'No sessions yet. Your booking appears here once we’ve confirmed it.';
const _noPackage = 'Choose a package first, then pick a time for your session.';

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

  Future<void> pump(WidgetTester tester, Widget home, {double width = 1440, Brightness brightness = Brightness.light}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(
      auth: FakeAuthService(signedInAs: testUser),
      bookings: FakeBookingService(),
      brightness: brightness,
      home: home,
    ));
    await tester.pumpAndSettle();
  }

  final pages = [
    ('Your sessions', const ProfilePage(), _noSessions),
    ('Book a session', const SchedulingPage(packageName: ''), _noPackage),
  ];

  /// The band's painted box.
  final bandBox = find.descendant(of: find.byType(EmptyState), matching: find.byType(DecoratedBox)).first;
  BoxDecoration band(WidgetTester tester) => tester.widget<DecoratedBox>(bandBox).decoration as BoxDecoration;

  for (final (page, home, sentence) in pages) {
    for (final brightness in Brightness.values) {
      testWidgets('$page (${brightness.name}): a sunk band, the sentence in body and ink, "See packages" inside',
          (tester) async {
        await pump(tester, home, brightness: brightness);
        final c = brightness == Brightness.dark ? BrookieColors.dark : BrookieColors.light;

        expect(band(tester).color, c.surfaceSunk);
        expect(band(tester).borderRadius, BorderRadius.circular(BrookieRadius.md));
        final style = tester.renderObject<RenderParagraph>(find.text(sentence)).text.style!;
        expect(style.fontFamily, BrookieType.body.fontFamily);
        expect(style.fontSize, BrookieType.body.fontSize);
        expect(style.color, c.ink);

        final box = tester.getRect(bandBox);
        final text = tester.getRect(find.text(sentence));
        final button = tester.getRect(find.widgetWithText(OutlinedButton, 'See packages'));
        expect(text.topLeft - box.topLeft, const Offset(BrookieSpace.s5, BrookieSpace.s5));
        expect(button.left, text.left);
        expect(button.top - text.bottom, BrookieSpace.s4);
        expect(box.bottom - button.bottom, BrookieSpace.s5);
        expect(button.height, greaterThanOrEqualTo(44));
        expect(box.width, EmptyState.maxWidth);
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in [740.0, 768.0, 1024.0, 1440.0]) {
      testWidgets('$page at ${width.round()}px: the sentence sets on one line', (tester) async {
        await pump(tester, home, width: width);

        final text = tester.getSize(find.text(sentence));
        expect(text.height, BrookieType.body.fontSize! * BrookieType.body.height!);
        expect(text.width, lessThanOrEqualTo(BrookieSize.readingWidth));
      });
    }

    for (final width in [320.0, 390.0]) {
      testWidgets('$page at ${width.round()}px: the band fills the column and nothing overflows', (tester) async {
        await pump(tester, home, width: width);

        final gutter = BrookieSpace.s4;
        expect(tester.getRect(bandBox).left, gutter);
        expect(tester.getRect(bandBox).width, width - 2 * gutter);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the two pages show the same band', (tester) async {
    await pump(tester, const ProfilePage());
    final sessions = band(tester);
    await pump(tester, const SchedulingPage(packageName: ''));

    expect(band(tester), sessions);
  });
}
