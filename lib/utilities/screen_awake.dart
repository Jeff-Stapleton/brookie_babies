import 'package:flutter/foundation.dart';

/// Whether a page needs the screen kept on: a download being prepared,
/// whose connection a phone drops when it locks.
///
/// Pages that need it [set] it on while they do, and off in dispose. While
/// it's [active], main.dart asks the browser to keep the screen on (the
/// Screen Wake Lock API). This file is pure Dart, so pages that use it are
/// tested on the VM.
abstract final class ScreenAwake {
  static final _owners = <Object>{};
  static final _active = ValueNotifier<bool>(false);

  /// True while any owner needs the screen on.
  static ValueListenable<bool> get active => _active;

  /// Records whether [owner] (usually a page's State) needs the screen kept
  /// on. Safe to repeat.
  static void set(Object owner, bool on) {
    if (on) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    _active.value = _owners.isNotEmpty;
  }

  /// Forgets every owner, so one test's leftover request can't reach the
  /// next.
  @visibleForTesting
  static void reset() {
    _owners.clear();
    _active.value = false;
  }
}
