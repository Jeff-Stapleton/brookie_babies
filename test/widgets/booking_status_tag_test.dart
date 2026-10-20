import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/booking_status_tag.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (status, label, tone, icon) in [
    (BookingStatus.paid, 'Paid', StatusTone.success, Icons.check),
    (BookingStatus.pending, 'Payment pending', StatusTone.neutral, null),
    (BookingStatus.cancelled, 'Cancelled', StatusTone.neutral, null),
    (BookingStatus.refunded, 'Refunded', StatusTone.neutral, null),
    (BookingStatus.adhoc, 'Ad hoc', StatusTone.neutral, null),
  ]) {
    testWidgets('${status.name}: "$label"', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: brookieTheme(Brightness.light),
        home: Scaffold(body: BookingStatusTag(status: status)),
      ));

      final tag = tester.widget<StatusTag>(find.byType(StatusTag));
      expect(tag.label, label);
      expect(tag.tone, tone);
      expect(tag.icon, icon);
    });
  }
}
