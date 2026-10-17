import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Whether the last input was a key press rather than a pointer, like the
/// browser's :focus-visible.
///
/// Flutter shows focus after any mouse use on desktop, so a control that gets
/// focus without a key press (a dialog's first action, the account avatar
/// once its menu opens) would look keyboard-focused after a click. Such
/// controls show their focus ring only while [lastWasKey] is true.
abstract final class KeyboardInput {
  static final _lastWasKey = ValueNotifier<bool>(false);
  static PointerRouter? _router;

  /// Whether the most recent input was a key press. A pointer going down
  /// (mouse, touch or pen) makes it false again.
  static bool get lastWasKey => _lastWasKey.value;

  /// Notifies when [lastWasKey] changes, so a focused control can show or
  /// hide its ring when the family switches between mouse and keyboard.
  static ValueListenable<bool> get changes => _lastWasKey;

  /// Starts watching input. Safe to call any number of times: it watches
  /// once, and picks up again if the keyboard's handlers were cleared (as
  /// widget tests do between tests).
  static void listen() {
    // A key that is still down (such as the Enter that opened a dialog)
    // came from the keyboard, even though it went down before this call.
    if (HardwareKeyboard.instance.logicalKeysPressed.isNotEmpty) _lastWasKey.value = true;
    HardwareKeyboard.instance
      ..removeHandler(_onKey)
      ..addHandler(_onKey);
    final router = GestureBinding.instance.pointerRouter;
    if (!identical(router, _router)) {
      router.addGlobalRoute(_onPointer);
      _router = router;
    }
  }

  static bool _onKey(KeyEvent event) {
    _lastWasKey.value = true;
    return false; // Only watching; the key still does what it does.
  }

  static void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) _lastWasKey.value = false;
  }
}
