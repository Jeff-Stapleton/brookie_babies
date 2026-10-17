import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:brookie_babies/components/account_button.dart';
import 'package:brookie_babies/components/booking_calendar.dart';
import 'package:brookie_babies/components/session_list.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/session_package.dart';
import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/payment_links.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:table_calendar/table_calendar.dart' show isSameDay;

/// Booking: pick a day and a session time for [packageName], then continue to
/// Stripe to pay.
class SchedulingPage extends StatefulWidget {
  const SchedulingPage({super.key, required this.packageName, this.now});

  final String packageName;

  /// The current time, which decides the first bookable day and which of
  /// today's times have passed. Defaults to the clock; tests pin it.
  final DateTime? now;

  @override
  State<SchedulingPage> createState() => _SchedulingPageState();
}

class _SchedulingPageState extends State<SchedulingPage> {
  late final DateTime _now = widget.now ?? DateTime.now();
  late final DateTime _firstDay = firstBookableDay(_now);
  late final DateTime _lastDay = lastBookableDay(_now);

  // Open with a day already chosen, so its times show straight away.
  late DateTime _selectedDay = _firstOpenDay();
  SessionTime? _selectedTime;

  /// The times still ahead on [day]: today's earlier times have gone.
  List<SessionTime> _timesOn(DateTime day) =>
      [for (final time in SessionTime.all) if (time.startOn(day).isAfter(_now)) time];

  bool _isOpen(DateTime day) => _timesOn(day).isNotEmpty;

  DateTime _firstOpenDay() {
    for (var day = _firstDay; !day.isAfter(_lastDay); day = DateTime(day.year, day.month, day.day + 1)) {
      if (_isOpen(day)) return day;
    }
    return _firstDay;
  }

  void _selectDay(DateTime day) {
    if (isSameDay(day, _selectedDay)) return;
    setState(() {
      _selectedDay = day;
      // A time belongs to its day; choosing another day starts over.
      _selectedTime = null;
    });
  }

  /// Opens the package's Stripe Payment Link, asking the visitor to sign in
  /// first so the payment can be matched to their account.
  Future<void> navigateCheckout() async {
    if (!kPaymentLinks.containsKey(widget.packageName)) {
      log('Unknown package type');
      return;
    }
    final services = AppServices.of(context);
    final user = services.auth.currentUser ?? await showSignInDialog(context, toBook: true);
    if (user == null || !mounted) return;

    final uri = paymentLinkUri(widget.packageName, uid: user.uid, email: user.email)!;
    // Same tab: after the sign-in dialog, opening a new tab is no longer part
    // of the tap, so the browser could block it as a popup.
    await services.openUrl(uri, webOnlyWindowName: '_self');
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final text = Theme.of(context).textTheme;
    final package = SessionPackage.named(widget.packageName);
    final wide = MediaQuery.sizeOf(context).width >= BrookieBreakpoint.wide;
    final canGoBack = ModalRoute.of(context)?.canPop ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: canGoBack
            ? IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        automaticallyImplyLeading: false,
        title: const Text('Book a session'),
        actions: const [AccountButton(), SizedBox(width: BrookieSpace.s4)],
      ),
      body: SingleChildScrollView(
        child: ContentWidth(
          child: Padding(
            padding: EdgeInsets.only(
              top: wide ? BrookieSpace.s7 : BrookieSpace.s6,
              bottom: BrookieLayout.sectionGap(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text('Pick a session time', style: text.headlineLarge)),
                if (package != null) ...[
                  const SizedBox(height: BrookieSpace.s2),
                  Text(
                    '${package.name} session · ${package.priceLabel}',
                    style: text.bodyMedium!.copyWith(color: c.inkSoft),
                  ),
                ],
                const SizedBox(height: BrookieSpace.s6),
                if (package == null) const _NoPackage() else _buildBooking(wide),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBooking(bool wide) {
    final calendar = BookingCalendar(
      firstDay: _firstDay,
      lastDay: _lastDay,
      today: _now,
      selectedDay: _selectedDay,
      isOpen: _isOpen,
      onDaySelected: _selectDay,
    );
    final times = _TimesColumn(
      day: _selectedDay,
      times: _timesOn(_selectedDay),
      selected: _selectedTime,
      onSelected: (time) => setState(() => _selectedTime = time),
      onContinue: navigateCheckout,
      blockButton: !wide,
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [calendar, const SizedBox(height: BrookieSpace.s6), times],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: BookingCalendar.maxWidth, child: calendar),
        const SizedBox(width: BrookieSpace.s8),
        Flexible(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: _TimesColumn.maxWidth), child: times),
        ),
      ],
    );
  }
}

/// The selected day's times, then the one action the page is for.
class _TimesColumn extends StatelessWidget {
  const _TimesColumn({
    required this.day,
    required this.times,
    required this.selected,
    required this.onSelected,
    required this.onContinue,
    required this.blockButton,
  });

  final DateTime day;
  final List<SessionTime> times;
  final SessionTime? selected;
  final ValueChanged<SessionTime> onSelected;
  final VoidCallback onContinue;

  /// Whether the button fills the column (phones) or fits its label.
  final bool blockButton;

  static const maxWidth = 520.0;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final fine = BrookieType.small.copyWith(color: c.inkSoft);
    final button = FilledButton(
      onPressed: selected == null ? null : onContinue,
      child: const Text('Continue to payment'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SessionList(day: day, times: times, selected: selected, onSelected: onSelected),
        const SizedBox(height: BrookieSpace.s5),
        if (blockButton) SizedBox(width: double.infinity, child: button) else button,
        const SizedBox(height: BrookieSpace.s3),
        // Says why the button is disabled; once a time is chosen, what it
        // will book.
        Semantics(
          liveRegion: true,
          child: Text(
            selected == null ? 'Choose a time to continue.' : '${formatDayShort(day)}, ${selected!.label}',
            style: fine,
          ),
        ),
        const SizedBox(height: BrookieSpace.s1),
        Row(
          children: [
            Icon(Icons.lock_outline, size: 14, color: c.inkSoft),
            const SizedBox(width: BrookieSpace.s1),
            Flexible(child: Text('Payments are processed by Stripe.', style: fine)),
          ],
        ),
      ],
    );
  }
}

/// Shown when the page was opened without a package (the bare /schedule
/// route): nothing to book yet, and a way back to the packages.
class _NoPackage extends StatelessWidget {
  const _NoPackage();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InlineMessage(
            tone: StatusTone.neutral,
            message: 'Choose a package first, then pick a time for your session.',
          ),
          const SizedBox(height: BrookieSpace.s4),
          OutlinedButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('See packages'),
          ),
        ],
      ),
    );
  }
}
