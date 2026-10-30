import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/busy_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int presses;

  setUp(() => presses = 0);

  Future<void> pumpButton(WidgetTester tester, {required bool busy, BusyButtonKind kind = BusyButtonKind.filled,
      bool enabled = true}) async {
    await tester.pumpWidget(MaterialApp(
      theme: brookieTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: BusyButton(
            label: 'Save changes',
            busyLabel: 'Saving changes…',
            busy: busy,
            kind: kind,
            icon: Icons.check,
            onPressed: enabled ? () => presses++ : null,
          ),
        ),
      ),
    ));
  }

  testWidgets('presses do what it says', (tester) async {
    await pumpButton(tester, busy: false);

    await tester.tap(find.text('Save changes'));
    expect(presses, 1);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  for (final kind in BusyButtonKind.values) {
    testWidgets('busy (${kind.name}): says so with a spinner, stays enabled, and ignores presses', (tester) async {
      await pumpButton(tester, busy: true, kind: kind);

      expect(find.text('Saving changes…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      final button = tester.widget<ButtonStyleButton>(
          find.byWidgetPredicate((widget) => widget is ButtonStyleButton));
      expect(button.onPressed, isNotNull);
      expect(button.style!.foregroundColor!.resolve({}), BrookieColors.light.inkSoft);

      await tester.tap(find.text('Saving changes…'));
      expect(presses, 0);
    });
  }

  testWidgets('busy under reduced motion: a still hourglass instead of the spinner', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: brookieTheme(Brightness.light),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: Center(
            child: BusyButton(
              label: 'Save changes',
              busyLabel: 'Saving changes…',
              busy: true,
              icon: Icons.check,
              onPressed: () => presses++,
            ),
          ),
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    final hourglass = find.byIcon(Icons.hourglass_empty);
    expect(hourglass, findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    // Ink-soft, like the busy label.
    final glyph = tester.widget<RichText>(find.descendant(of: hourglass, matching: find.byType(RichText)));
    expect(glyph.text.style!.color, BrookieColors.light.inkSoft);
    expect(find.text('Saving changes…'), findsOneWidget);
    // Nothing moves, so the frames settle.
    await tester.pumpAndSettle();
  });

  testWidgets('the filled kind is the theme’s FilledButton; null onPressed disables it', (tester) async {
    await pumpButton(tester, busy: false, enabled: false);

    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('screen readers hear the busy label', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpButton(tester, busy: true);

    expect(
      tester.getSemantics(find.byType(FilledButton)),
      isSemantics(label: 'Saving changes…', isButton: true, isEnabled: true, isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('a busy label that counts is heard as the steady busySemanticsLabel, so it’s announced once',
      (tester) async {
    final semantics = tester.ensureSemantics();
    Future<void> pumpAt(int done) => tester.pumpWidget(MaterialApp(
          theme: brookieTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: BusyButton(
                label: 'Delete all photos',
                busyLabel: 'Deleting $done of 3…',
                busySemanticsLabel: 'Deleting 3 photos…',
                busy: true,
                kind: BusyButtonKind.text,
                onPressed: () {},
              ),
            ),
          ),
        ));

    for (final done in [0, 2]) {
      await pumpAt(done);
      expect(find.text('Deleting $done of 3…'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(TextButton)),
        isSemantics(label: 'Deleting 3 photos…', isButton: true, isLiveRegion: true),
      );
    }
    semantics.dispose();
  });
}
