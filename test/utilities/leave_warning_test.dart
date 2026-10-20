import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(LeaveWarning.reset);

  test('off until an owner has work to lose', () {
    expect(LeaveWarning.active.value, isFalse);

    final page = Object();
    LeaveWarning.set(page, true);
    expect(LeaveWarning.active.value, isTrue);

    LeaveWarning.set(page, false);
    expect(LeaveWarning.active.value, isFalse);
  });

  test('stays on while any owner has work to lose', () {
    final uploads = Object();
    final edits = Object();
    LeaveWarning.set(uploads, true);
    LeaveWarning.set(edits, true);

    LeaveWarning.set(uploads, false);
    expect(LeaveWarning.active.value, isTrue);

    LeaveWarning.set(edits, false);
    expect(LeaveWarning.active.value, isFalse);
  });

  test('repeating a setting changes nothing, and notifies only on a change', () {
    final page = Object();
    var notified = 0;
    void count() => notified++;
    LeaveWarning.active.addListener(count);
    addTearDown(() => LeaveWarning.active.removeListener(count));

    LeaveWarning.set(page, true);
    LeaveWarning.set(page, true);
    expect(notified, 1);

    LeaveWarning.set(page, false);
    LeaveWarning.set(page, false);
    // Clearing an owner that never set it is harmless too.
    LeaveWarning.set(Object(), false);
    expect(notified, 2);
    expect(LeaveWarning.active.value, isFalse);
  });

  test('reset forgets every owner', () {
    LeaveWarning.set(Object(), true);

    LeaveWarning.reset();

    expect(LeaveWarning.active.value, isFalse);
  });
}
