import 'package:brookie_babies/models/session_package.dart';
import 'package:brookie_babies/services/payment_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every package has a Payment Link, and every link a package', () {
    // Booking shows a package without a link as unavailable, so a package
    // added or renamed without its link would quietly stop taking bookings.
    expect(kPaymentLinks.keys.toSet(), {for (final package in SessionPackage.all) package.name});
  });

  test('finds a package by its exact name', () {
    expect(SessionPackage.named('Premium')?.price, 50);
    expect(SessionPackage.named('premium'), isNull);
    expect(SessionPackage.named(''), isNull);
  });

  test('shows prices in whole dollars', () {
    expect(SessionPackage.named('Basic')!.priceLabel, '\$25');
  });
}
