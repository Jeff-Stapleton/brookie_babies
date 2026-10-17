import 'package:brookie_babies/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const valid = {
    'uid': 'uid123',
    'packageName': 'Premium',
    'date': '2026-11-14',
    'time': '09:30',
    'location': '10652 S Wild Rice Dr.',
    'status': 'paid',
    'photosReady': true,
  };

  test('reads every field', () {
    final booking = Booking.fromMap('b1', valid)!;

    expect(booking.id, 'b1');
    expect(booking.packageName, 'Premium');
    expect(booking.date, DateTime(2026, 11, 14));
    expect(booking.time, (hour: 9, minute: 30));
    expect(booking.location, '10652 S Wild Rice Dr.');
    expect(booking.status, BookingStatus.paid);
    expect(booking.photosReady, isTrue);
  });

  test('optional fields default to absent', () {
    final booking = Booking.fromMap('b1', {
      'packageName': 'Basic',
      'date': '2026-11-14',
      'status': 'pending',
    })!;

    expect(booking.time, isNull);
    expect(booking.location, isNull);
    expect(booking.status, BookingStatus.pending);
    expect(booking.photosReady, isFalse);
  });

  test('drops malformed optional fields', () {
    final booking = Booking.fromMap('b1', {...valid, 'time': '9:30am', 'location': '', 'photosReady': 'yes'})!;

    expect(booking.time, isNull);
    expect(booking.location, isNull);
    expect(booking.photosReady, isFalse);
  });

  test('forgives spaces and the case of status in hand-typed fields', () {
    final booking = Booking.fromMap('b1', {
      'packageName': ' Premium ',
      'date': '2026-11-14 ',
      'time': ' 09:30',
      'status': 'Paid',
    })!;

    expect(booking.packageName, 'Premium');
    expect(booking.date, DateTime(2026, 11, 14));
    expect(booking.time, (hour: 9, minute: 30));
    expect(booking.status, BookingStatus.paid);
  });

  test('rejects documents missing required fields or with bad values', () {
    for (final bad in [
      {...valid}..remove('packageName'),
      {...valid}..remove('date'),
      {...valid}..remove('status'),
      {...valid, 'date': '11/14/2026'},
      {...valid, 'date': '2026-02-30'},
      {...valid, 'status': 'booked'},
      {...valid, 'packageName': '  '},
      {...valid, 'date': 20261114},
    ]) {
      expect(Booking.fromMap('b1', bad), isNull, reason: '$bad');
    }
  });

  test('isPast compares whole days', () {
    final booking = Booking.fromMap('b1', valid)!;

    expect(booking.isPast(DateTime(2026, 11, 14, 23, 59)), isFalse);
    expect(booking.isPast(DateTime(2026, 11, 15, 0, 1)), isTrue);
  });

  test('compareTo orders by date, then time', () {
    Booking at(String date, String? time) =>
        Booking.fromMap('id', {...valid, 'date': date, 'time': time})!;

    final sorted = [at('2026-11-15', '09:00'), at('2026-11-14', '13:00'), at('2026-11-14', '09:00')]
      ..sort((a, b) => a.compareTo(b));

    expect(sorted.map((b) => (b.date.day, b.time?.hour)), [(14, 9), (14, 13), (15, 9)]);
  });
}
