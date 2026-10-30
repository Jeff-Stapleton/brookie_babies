import 'package:flutter/foundation.dart';

/// Whether leaving the site now would lose work: uploads still running, a
/// download being prepared, or changes not yet saved.
///
/// Pages that hold such work [set] it on while they do, and off in dispose.
/// While it's [active], main.dart has the browser ask before the tab closes
/// or reloads, and the account menu asks before signing out.
abstract final class LeaveWarning {
  static final _owners = <Object>{};
  static final _active = ValueNotifier<bool>(false);

  /// True while any owner has work to lose.
  static ValueListenable<bool> get active => _active;

  /// Records whether [owner] (usually a page's State) has work that leaving
  /// would lose. Safe to repeat.
  static void set(Object owner, bool on) {
    if (on) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    _active.value = _owners.isNotEmpty;
  }

  /// Forgets every owner, so one test's leftover warning can't reach the
  /// next.
  @visibleForTesting
  static void reset() {
    _owners.clear();
    _active.value = false;
  }
}
