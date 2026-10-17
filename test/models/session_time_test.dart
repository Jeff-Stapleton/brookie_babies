import 'package:brookie_babies/models/session_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('labels a time range with an en dash and lowercase am/pm', () {
    expect(const SessionTime(9).label, '9:00–9:30 am');
    expect(const SessionTime(13).label, '1:00–1:30 pm');
    expect(const SessionTime(12).label, '12:00–12:30 pm');
    expect(const SessionTime(0, 15).label, '12:15–12:45 am');
  });

  test('names both periods when a session crosses noon or midnight', () {
    expect(const SessionTime(11, 45).label, '11:45 am–12:15 pm');
    expect(const SessionTime(23, 45).label, '11:45 pm–12:15 am');
  });

  test('starts on the given day in local time', () {
    expect(const SessionTime(14).startOn(DateTime.utc(2026, 10, 24)), DateTime(2026, 10, 24, 14));
  });

  test('offers the placeholder times, earliest first', () {
    expect(SessionTime.all.map((time) => time.label), [
      '9:00–9:30 am',
      '10:00–10:30 am',
      '11:00–11:30 am',
      '1:00–1:30 pm',
      '2:00–2:30 pm',
    ]);
  });

  test('times with the same hour and minute are equal', () {
    // Built at run time, so not the same instance as the constant.
    expect(SessionTime(int.parse('10')), const SessionTime(10));
    expect(const SessionTime(10).hashCode, const SessionTime(10, 0).hashCode);
    expect(const SessionTime(10), isNot(const SessionTime(10, 30)));
  });
}
