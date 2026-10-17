import 'package:brookie_babies/utilities/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final saturday = DateTime(2026, 10, 24);

  test('formats days for headings and lists', () {
    expect(formatDayHeading(saturday), 'Saturday, October 24');
    expect(formatDayShort(saturday), 'Sat, Oct 24');
    expect(formatDayHeading(DateTime.utc(2027, 1, 4)), 'Monday, January 4');
    expect(formatDayShort(DateTime(2026, 9, 1)), 'Tue, Sep 1');
  });

  test('formats a calendar month and its weekday initials', () {
    expect(formatMonth(saturday), 'October 2026');
    expect([for (var day = 18; day <= 24; day++) weekdayInitial(DateTime(2026, 10, day))].join(), 'SMTWTFS');
  });

  test('books from today until about three months out', () {
    final now = DateTime(2026, 10, 17, 15, 30);
    expect(firstBookableDay(now), DateTime(2026, 10, 17));
    expect(lastBookableDay(now), DateTime(2027, 1, 17));
  });
}
