import 'package:flutter/foundation.dart';

/// A time of day families can book a session at.
@immutable
class SessionTime {
  const SessionTime(this.hour, [this.minute = 0]);

  /// 0–23.
  final int hour;
  final int minute;

  /// How long each booking holds the studio.
  static const length = Duration(minutes: 30);

  /// The times offered on every open day, earliest first.
  ///
  /// Placeholders: real availability isn't modeled yet, and the Stripe Payment
  /// Links don't carry the chosen day or time (AGENT.md), so nothing marks a
  /// time as taken. Change the times here; everything else follows.
  static const all = [
    SessionTime(9),
    SessionTime(10),
    SessionTime(11),
    SessionTime(13),
    SessionTime(14),
  ];

  /// When this session starts on [day], in local time.
  DateTime startOn(DateTime day) => DateTime(day.year, day.month, day.day, hour, minute);

  /// The time range as the site writes it: "9:00–9:30 am", or
  /// "11:45 am–12:15 pm" when it crosses noon.
  String get label {
    final start = hour * 60 + minute;
    final end = start + length.inMinutes;
    final startPeriod = _period(start);
    final endPeriod = _period(end);
    return startPeriod == endPeriod
        ? '${_clock(start)}–${_clock(end)} $endPeriod'
        : '${_clock(start)} $startPeriod–${_clock(end)} $endPeriod';
  }

  static String _clock(int minutes) {
    final hour = minutes ~/ 60 % 12;
    return '${hour == 0 ? 12 : hour}:${(minutes % 60).toString().padLeft(2, '0')}';
  }

  static String _period(int minutes) => minutes ~/ 60 % 24 < 12 ? 'am' : 'pm';

  @override
  bool operator ==(Object other) => other is SessionTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => label;
}
