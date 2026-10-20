import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/brookie_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool? result;

  /// Opens a confirmation from a button and keeps what it completes with.
  Future<void> openConfirm(
    WidgetTester tester, {
    bool destructive = false,
    String cancelLabel = 'Cancel',
    Brightness brightness = Brightness.light,
    Size? size,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    result = null;
    await tester.pumpWidget(MaterialApp(
      theme: brookieTheme(brightness),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showBrookieConfirm(
              context,
              title: 'Delete this photo?',
              message: 'IMG_1.jpg will be deleted for good.',
              confirmLabel: 'Delete photo',
              cancelLabel: cancelLabel,
              destructive: destructive,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Material surface(WidgetTester tester, String label) => tester
      .widget<Material>(find.descendant(of: find.widgetWithText(FilledButton, label), matching: find.byType(Material)));

  bool hasFocus(WidgetTester tester, String label) => Focus.of(tester.element(find.text(label))).hasPrimaryFocus;

  testWidgets('shows the title and message; confirming completes with true', (tester) async {
    await openConfirm(tester);

    expect(find.text('Delete this photo?'), findsOneWidget);
    expect(find.text('IMG_1.jpg will be deleted for good.'), findsOneWidget);
    await tester.tap(find.text('Delete photo'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byType(BrookieDialog), findsNothing);
  });

  testWidgets('Cancel completes with false', (tester) async {
    await openConfirm(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('a click outside or Escape completes with false', (tester) async {
    await openConfirm(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await openConfirm(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('the dismissal can be named', (tester) async {
    await openConfirm(tester, cancelLabel: 'Keep photo');

    expect(find.widgetWithText(TextButton, 'Keep photo'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('an ordinary confirmation is ink and takes focus, its ring only for the keyboard', (tester) async {
    await openConfirm(tester);

    expect(surface(tester, 'Delete photo').color, BrookieColors.light.ink);
    expect(hasFocus(tester, 'Delete photo'), isTrue);
    // Opened by a tap: no ring.
    expect((surface(tester, 'Delete photo').shape! as OutlinedBorder).side, BorderSide.none);

    await tester.sendKeyEvent(LogicalKeyboardKey.shift);
    await tester.pumpAndSettle();
    expect((surface(tester, 'Delete photo').shape! as OutlinedBorder).side,
        brookieFocusSide(BrookieColors.light.focus));
  });

  for (final brightness in Brightness.values) {
    testWidgets('a destructive one is danger-filled and leaves focus alone (${brightness.name})', (tester) async {
      await openConfirm(tester, destructive: true, brightness: brightness);
      final colors = brightness == Brightness.dark ? BrookieColors.dark : BrookieColors.light;

      expect(surface(tester, 'Delete photo').color, colors.danger);
      expect(hasFocus(tester, 'Delete photo'), isFalse);
      expect(hasFocus(tester, 'Cancel'), isFalse);

      // Enter meant for the page confirms nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(BrookieDialog), findsOneWidget);

      // Tab reaches it, and the keyboard ring shows.
      for (var i = 0; i < 3 && !hasFocus(tester, 'Delete photo'); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(hasFocus(tester, 'Delete photo'), isTrue);
      expect((surface(tester, 'Delete photo').shape! as OutlinedBorder).side, brookieFocusSide(colors.focus));
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('on a 320px phone the actions stack, the primary first (${brightness.name})', (tester) async {
      await openConfirm(tester, brightness: brightness, size: const Size(320, 640));

      expect(tester.takeException(), isNull);
      final primary = tester.getRect(find.widgetWithText(FilledButton, 'Delete photo'));
      final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
      expect(primary.bottom, lessThan(cancel.top));
      expect(primary.width, cancel.width);
    });
  }

  testWidgets('screen readers hear the title', (tester) async {
    final semantics = tester.ensureSemantics();
    await openConfirm(tester);

    expect(find.bySemanticsLabel('Delete this photo?'), findsWidgets);
    semantics.dispose();
  });
}
