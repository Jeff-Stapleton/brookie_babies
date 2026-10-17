// The outlined button's focus ring: the button keeps its own edge, then a 2px
// gap, then the 2px ring, so focus never looks like hover.

import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpButton(WidgetTester tester, Brightness brightness) async {
    await tester.pumpWidget(MaterialApp(
      theme: brookieTheme(brightness),
      home: Scaffold(
        body: Center(child: OutlinedButton(onPressed: () {}, child: const Text('See packages'))),
      ),
    ));
  }

  final button = find.byType(OutlinedButton);
  Material surface(WidgetTester tester) =>
      tester.widget<Material>(find.descendant(of: button, matching: find.byType(Material)));
  OutlinedBorder shape(WidgetTester tester) => surface(tester).shape! as OutlinedBorder;

  Future<void> hover(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(button));
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    final c = brightness == Brightness.dark ? BrookieColors.dark : BrookieColors.light;
    final edge = BorderSide(color: c.lineStrong, width: 1.5);
    final inkEdge = BorderSide(color: c.ink, width: 1.5);
    final ring = brookieFocusSide(c.focus);

    group(brightness == Brightness.dark ? 'Darkroom' : 'Print', () {
      testWidgets('at rest: a line-strong edge and no ring', (tester) async {
        await pumpButton(tester, brightness);

        expect(shape(tester), isNot(isA<FocusRingBorder>()));
        expect(shape(tester).side, edge);
      });

      testWidgets('keyboard focus keeps the edge and adds the ring outside it', (tester) async {
        await pumpButton(tester, brightness);
        await tab(tester);

        final focused = shape(tester);
        expect(focused, isA<FocusRingBorder>());
        expect(focused.side, edge);
        expect(focused.side, isNot(BorderSide.none));
        expect((focused as FocusRingBorder).ring, ring);
        // The ring paints 2–4px outside the button, which mustn't clip it.
        expect(surface(tester).clipBehavior, Clip.none);
      });

      testWidgets('hover is an ink edge with no ring, unlike focus', (tester) async {
        await pumpButton(tester, brightness);
        await hover(tester);

        expect(shape(tester), isNot(isA<FocusRingBorder>()));
        expect(shape(tester).side, inkEdge);

        await tab(tester);
        expect(shape(tester), isA<FocusRingBorder>());
        expect(shape(tester).side, inkEdge);
        expect((shape(tester) as FocusRingBorder).ring, ring);
      });
    });
  }

  testWidgets('FocusRingBorder paints the edge, then the ring 2px outside it', (tester) async {
    final c = BrookieColors.light;
    const size = Size(160, 52);
    await tester.pumpWidget(Center(
      child: SizedBox.fromSize(
        size: size,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: FocusRingBorder(
              shape: StadiumBorder(side: BorderSide(color: c.lineStrong, width: 1.5)),
              ring: brookieFocusSide(c.focus),
            ),
          ),
        ),
      ),
    ));

    final bounds = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(26));
    expect(
      tester.renderObject(find.byType(DecoratedBox)),
      paints
        // The 1.5px edge, inside the button's bounds.
        ..rrect(rrect: bounds.deflate(0.75), color: c.lineStrong, strokeWidth: 1.5, style: PaintingStyle.stroke)
        // The 2px ring centred 3px out: a 2px gap, then 2–4px out.
        ..rrect(rrect: bounds.inflate(3), color: c.focus, strokeWidth: 2, style: PaintingStyle.stroke),
    );
  });

  test('FocusRingBorder fades its ring in and out', () {
    final c = BrookieColors.light;
    final edge = StadiumBorder(side: BorderSide(color: c.lineStrong, width: 1.5));
    final focused = FocusRingBorder(shape: edge, ring: brookieFocusSide(c.focus));

    final fadingIn = ShapeBorder.lerp(edge, focused, 0.25)! as FocusRingBorder;
    expect(fadingIn.side, edge.side);
    expect(fadingIn.ring.color.a, moreOrLessEquals(0.25));
    final fadingOut = ShapeBorder.lerp(focused, edge, 0.25)! as FocusRingBorder;
    expect(fadingOut.ring.color.a, moreOrLessEquals(0.75));
    expect(ShapeBorder.lerp(edge, focused, 1), focused);
    expect(focused.copyWith(side: BorderSide.none).ring, focused.ring);
  });
}
