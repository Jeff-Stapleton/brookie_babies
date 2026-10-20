import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';

/// A booking's status as a [StatusTag]: "Paid", "Payment pending",
/// "Cancelled", "Refunded" or "Ad hoc".
///
/// Families never see "Ad hoc" (BookingCard leaves the tag off those): it's
/// the admin's word for a session added without a purchase.
class BookingStatusTag extends StatelessWidget {
  const BookingStatusTag({super.key, required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      BookingStatus.paid => const StatusTag(label: 'Paid', tone: StatusTone.success, icon: Icons.check),
      BookingStatus.pending => const StatusTag(label: 'Payment pending'),
      BookingStatus.cancelled => const StatusTag(label: 'Cancelled'),
      BookingStatus.refunded => const StatusTag(label: 'Refunded'),
      BookingStatus.adhoc => const StatusTag(label: 'Ad hoc'),
    };
  }
}
