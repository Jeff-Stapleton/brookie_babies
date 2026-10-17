// Dates as the site writes them, and the window families can book in.
//
// The site is English only, and package:intl isn't a direct dependency, so
// the names are spelled out here.

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A day in a heading: "Saturday, October 24".
String formatDayHeading(DateTime date) => '${_weekdays[date.weekday - 1]}, ${_months[date.month - 1]} ${date.day}';

/// A day in a list: "Sat, Oct 24". Given [now], a day in another year gets
/// its year: "Sat, Dec 13, 2025".
String formatDayShort(DateTime date, {DateTime? now}) {
  final day = '${_weekdays[date.weekday - 1].substring(0, 3)}, ${_months[date.month - 1].substring(0, 3)} ${date.day}';
  return now == null || now.year == date.year ? day : '$day, ${date.year}';
}

/// A calendar's month: "October 2026".
String formatMonth(DateTime date) => '${_months[date.month - 1]} ${date.year}';

/// A calendar's weekday heading: "S" for Saturday and Sunday alike.
String weekdayInitial(DateTime date) => _weekdays[date.weekday - 1][0];

/// The first day families can book: today. Nobody books the past.
DateTime firstBookableDay(DateTime now) => DateTime(now.year, now.month, now.day);

/// The last day families can book, about three months out.
DateTime lastBookableDay(DateTime now) => DateTime(now.year, now.month + 3, now.day);
