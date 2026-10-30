import 'package:brookie_babies/utilities/screen_awake.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ScreenAwake.reset);

  test('off until an owner needs the screen on', () {
    expect(ScreenAwake.active.value, isFalse);

    final page = Object();
    ScreenAwake.set(page, true);
    expect(ScreenAwake.active.value, isTrue);

    ScreenAwake.set(page, false);
    expect(ScreenAwake.active.value, isFalse);
  });

  test('stays on while any owner needs it', () {
    final first = Object();
    final second = Object();
    ScreenAwake.set(first, true);
    ScreenAwake.set(second, true);

    ScreenAwake.set(first, false);
    expect(ScreenAwake.active.value, isTrue);

    ScreenAwake.set(second, false);
    expect(ScreenAwake.active.value, isFalse);
  });

  test('repeating a setting changes nothing, and notifies only on a change', () {
    final page = Object();
    var notified = 0;
    void count() => notified++;
    ScreenAwake.active.addListener(count);
    addTearDown(() => ScreenAwake.active.removeListener(count));

    ScreenAwake.set(page, true);
    ScreenAwake.set(page, true);
    expect(notified, 1);

    ScreenAwake.set(page, false);
    ScreenAwake.set(page, false);
    // Clearing an owner that never set it is harmless too.
    ScreenAwake.set(Object(), false);
    expect(notified, 2);
    expect(ScreenAwake.active.value, isFalse);
  });

  test('reset forgets every owner', () {
    ScreenAwake.set(Object(), true);

    ScreenAwake.reset();

    expect(ScreenAwake.active.value, isFalse);
  });
}
