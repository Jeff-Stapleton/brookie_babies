import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/detail_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('an ink-soft icon, then the text (${brightness.name})', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: brookieTheme(brightness),
        home: const Scaffold(body: DetailLine(icon: Icons.place_outlined, text: 'Liberty Park')),
      ));

      final colors = brightness == Brightness.dark ? BrookieColors.dark : BrookieColors.light;
      final icon = tester.widget<Icon>(find.byIcon(Icons.place_outlined));
      expect(icon.size, 20);
      expect(icon.color, colors.inkSoft);
      expect(tester.getTopLeft(find.text('Liberty Park')).dx,
          tester.getTopRight(find.byIcon(Icons.place_outlined)).dx + BrookieSpace.s2);
    });
  }

  testWidgets('long text wraps beside the icon instead of overflowing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: brookieTheme(Brightness.light),
      home: const Scaffold(
        body: SizedBox(
          width: 200,
          child: DetailLine(icon: Icons.place_outlined, text: '1234 A Very Long Street Name, Salt Lake City, Utah'),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(DetailLine)).height, greaterThan(40));
  });
}
