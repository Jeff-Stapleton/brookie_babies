import 'package:brookie_babies/utilities/keyboard_input.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpBox(WidgetTester tester) =>
      tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: SizedBox.expand()));

  testWidgets('a key press sets lastWasKey; a pointer going down clears it', (tester) async {
    KeyboardInput.listen();
    await pumpBox(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(KeyboardInput.lastWasKey, isTrue);

    await tester.tapAt(const Offset(10, 10), kind: PointerDeviceKind.mouse);
    expect(KeyboardInput.lastWasKey, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(KeyboardInput.lastWasKey, isTrue);

    await tester.tapAt(const Offset(10, 10)); // a touch
    expect(KeyboardInput.lastWasKey, isFalse);
  });

  testWidgets('it only watches: the key still reaches the app', (tester) async {
    KeyboardInput.listen();
    var reached = 0;
    await tester.pumpWidget(Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) reached++;
        return KeyEventResult.handled;
      },
      child: const SizedBox.expand(),
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);

    expect(reached, 1);
    expect(KeyboardInput.lastWasKey, isTrue);
  });

  testWidgets('listen() is idempotent: one pointer route however often it is called', (tester) async {
    KeyboardInput.listen();
    final routes = GestureBinding.instance.pointerRouter.debugGlobalRouteCount;

    KeyboardInput.listen();
    KeyboardInput.listen();

    expect(GestureBinding.instance.pointerRouter.debugGlobalRouteCount, routes);
  });

  testWidgets('listen() picks up again after the keyboard handlers were cleared', (tester) async {
    KeyboardInput.listen();
    await pumpBox(tester);
    await tester.tapAt(const Offset(10, 10));
    HardwareKeyboard.instance.clearState();

    KeyboardInput.listen();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);

    expect(KeyboardInput.lastWasKey, isTrue);
  });

  testWidgets('a key still down when listening starts counts as the keyboard', (tester) async {
    KeyboardInput.listen();
    await pumpBox(tester);
    await tester.tapAt(const Offset(10, 10));
    expect(KeyboardInput.lastWasKey, isFalse);
    HardwareKeyboard.instance.clearState();
    // Enter goes down before anything listens, as when it opens a dialog.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    expect(KeyboardInput.lastWasKey, isFalse);

    KeyboardInput.listen();

    expect(KeyboardInput.lastWasKey, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  });

  testWidgets('notifies only when switching between keyboard and pointer', (tester) async {
    KeyboardInput.listen();
    await pumpBox(tester);
    await tester.tapAt(const Offset(10, 10));
    final seen = <bool>[];
    void record() => seen.add(KeyboardInput.lastWasKey);
    KeyboardInput.changes.addListener(record);
    addTearDown(() => KeyboardInput.changes.removeListener(record));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.tapAt(const Offset(10, 10));
    await tester.tapAt(const Offset(20, 20));

    expect(seen, [true, false]);
  });
}
