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

  test('reads who the session is for', () {
    final booking = Booking.fromMap('b1', {...valid, 'email': ' Parent@Example.com ', 'name': ' The Harper family '})!;

    expect(booking.uid, 'uid123');
    expect(booking.email, 'Parent@Example.com');
    expect(booking.name, 'The Harper family');
    expect(Booking.fromMap('b1', {...valid}..remove('uid'))!.uid, isNull);
    expect(Booking.fromMap('b1', {...valid, 'email': ' ', 'name': 7})!.email, isNull);
  });

  group('ad hoc sessions', () {
    const adHoc = {
      'status': 'adhoc',
      'name': 'The Harper family',
      'email': 'harper@example.com',
      'date': '2026-11-14',
      'photosReady': false,
    };

    test('need no package or uid', () {
      final booking = Booking.fromMap('a1', adHoc)!;

      expect(booking.status, BookingStatus.adhoc);
      expect(booking.isAdHoc, isTrue);
      expect(booking.packageName, isNull);
      expect(booking.uid, isNull);
      expect(booking.title, 'Photo session');
      expect(booking.name, 'The Harper family');
      expect(booking.email, 'harper@example.com');
    });

    test('the family sees the name the admin pages show', () {
      expect(Booking.fromMap('a1', adHoc)!.familyTitle, 'The Harper family');
      expect(Booking.fromMap('a1', {...adHoc, 'packageName': 'Ultimate'})!.familyTitle, 'The Harper family');
      // Typed in the console without one: its package, as before.
      expect(Booking.fromMap('a1', {...adHoc}..remove('name'))!.familyTitle, 'Photo session');
      expect(Booking.fromMap('a1', {...adHoc, 'name': ' '})!.familyTitle, 'Photo session');
    });

    test('may name a package', () {
      final booking = Booking.fromMap('a1', {...adHoc, 'packageName': 'Ultimate'})!;

      expect(booking.packageName, 'Ultimate');
      expect(booking.title, 'Ultimate session');
    });

    test('only as "adhoc": the rules and the download function match it exactly', () {
      for (final status in ['Adhoc', 'ADHOC', 'ad hoc', ' adhoc', 'adhoc ']) {
        expect(Booking.fromMap('a1', {...adHoc, 'status': status}), isNull, reason: status);
      }
    });
  });

  test('title names the package', () {
    expect(Booking.fromMap('b1', valid)!.title, 'Premium session');
  });

  test('the family sees a paid booking by its package: its name is for the Admin page', () {
    expect(Booking.fromMap('b1', {...valid, 'name': 'The Harper family'})!.familyTitle, 'Premium session');
  });

  test('photos can be delivered for paid and ad hoc sessions only', () {
    for (final (status, deliverable) in [
      ('paid', true),
      ('adhoc', true),
      ('pending', false),
      ('cancelled', false),
      ('refunded', false),
    ]) {
      final booking = Booking.fromMap('b1', {...valid, 'status': status})!;
      expect(booking.canDeliverPhotos, deliverable, reason: status);
      expect(booking.isAdHoc, status == 'adhoc', reason: status);
    }
  });

  test('problemWith names what keeps a document from being read', () {
    for (final (data, problem) in [
      ({...valid}..remove('packageName'), 'packageName is missing'),
      ({...valid, 'packageName': '  '}, 'packageName is missing'),
      ({...valid}..remove('date'), 'date isn’t YYYY-MM-DD'),
      ({...valid, 'date': '11/14/2026'}, 'date isn’t YYYY-MM-DD'),
      ({...valid, 'date': 20261114}, 'date isn’t YYYY-MM-DD'),
      ({...valid, 'date': '2026-02-30'}, 'date isn’t a real day'),
      ({...valid}..remove('status'), 'status isn’t paid, pending, cancelled, refunded or adhoc'),
      ({...valid, 'status': 'booked'}, 'status isn’t paid, pending, cancelled, refunded or adhoc'),
      ({...valid, 'status': 'AdHoc'}, 'status isn’t paid, pending, cancelled, refunded or adhoc'),
    ]) {
      expect(Booking.problemWith(data), problem, reason: '$data');
      expect(Booking.fromMap('b1', data), isNull, reason: '$data');
    }
    expect(Booking.problemWith(valid), isNull);
    expect(Booking.problemWith({'status': 'adhoc', 'date': '2026-11-14'}), isNull);
  });

  test('only ad hoc sessions may be made without a package', () {
    expect(() => Booking(id: 'b1', date: DateTime(2026, 11, 14)), throwsAssertionError);
    expect(Booking(id: 'a1', date: DateTime(2026, 11, 14), status: BookingStatus.adhoc).packageName, isNull);
  });
}
