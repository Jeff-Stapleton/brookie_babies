import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:brookie_babies/components/booking_calendar.dart';
import 'package:brookie_babies/components/session_list.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/session_package.dart';
import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/payment_links.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:brookie_babies/widgets/empty_state.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
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

  /// The package to book: null when the page was opened without one (the
  /// bare /schedule route), or for a package with no Payment Link to pay
  /// with, so the page never offers a booking it can't take.
  SessionPackage? get _package {
    final package = SessionPackage.named(widget.packageName);
    return package != null && kPaymentLinks.containsKey(package.name) ? package : null;
  }

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
    if (_package == null) {
      // Unreachable: the page offers no booking without a Payment Link.
      log('No Payment Link for package "${widget.packageName}"');
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
    final package = _package;
    final wide = MediaQuery.sizeOf(context).width >= BrookieBreakpoint.wide;

    return Scaffold(
      appBar: const BrookieTopBar(title: 'Book a session'),
      body: SingleChildScrollView(
        child: Padding(
          // The page frame Your sessions shares, so the titles line up.
          padding: EdgeInsets.only(
            top: wide ? BrookieSpace.s7 : BrookieSpace.s6,
            bottom: BrookieLayout.sectionGap(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ContentWidth(
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
                  ],
                ),
              ),
              const SizedBox(height: BrookieSpace.s6),
              if (package == null) const ContentWidth(child: _NoPackage()) else _buildBooking(context, wide),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBooking(BuildContext context, bool wide) {
    final width = MediaQuery.sizeOf(context).width;
    // On the narrowest phones a card inside the gutter can't fit seven
    // full-size days, so the calendar runs edge to edge instead.
    final edgeToEdge = !wide && width - 2 * BrookieLayout.gutter(context) < BookingCalendar.minCardWidth;
    final calendar = BookingCalendar(
      firstDay: _firstDay,
      lastDay: _lastDay,
      today: _now,
      selectedDay: _selectedDay,
      isOpen: _isOpen,
      onDaySelected: _selectDay,
      edgeToEdge: edgeToEdge,
    );
    final times = _TimesColumn(
      day: _selectedDay,
      now: _now,
      times: _timesOn(_selectedDay),
      selected: _selectedTime,
      onSelected: (time) => setState(() => _selectedTime = time),
      onContinue: navigateCheckout,
      // Phones fill the column; wider windows fit the label.
      blockButton: width < BrookieBreakpoint.gutter,
    );

    if (wide) {
      return ContentWidth(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: BookingCalendar.maxWidth, child: calendar),
            const SizedBox(width: BrookieSpace.s8),
            Flexible(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: _TimesColumn.maxWidth), child: times),
            ),
          ],
        ),
      );
    }
    // Stacked, the times end where the calendar card does, so the column has
    // one right edge.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (edgeToEdge) calendar else ContentWidth(child: Align(alignment: Alignment.topLeft, child: calendar)),
        const SizedBox(height: BrookieSpace.s6),
        ContentWidth(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: BookingCalendar.maxWidth), child: times),
          ),
        ),
      ],
    );
  }
}

/// The selected day's times, then the one action the page is for.
class _TimesColumn extends StatelessWidget {
  const _TimesColumn({
    required this.day,
    required this.now,
    required this.times,
    required this.selected,
    required this.onSelected,
    required this.onContinue,
    required this.blockButton,
  });

  final DateTime day;
  final DateTime now;
  final List<SessionTime> times;
  final SessionTime? selected;
  final ValueChanged<SessionTime> onSelected;
  final VoidCallback onContinue;

  /// Whether the button fills the column (phones) or fits its label.
  final bool blockButton;

  /// The column's widest beside the calendar. Under it, the column is as
  /// wide as the calendar ([BookingCalendar.maxWidth]).
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
            selected == null ? 'Choose a time to continue.' : '${formatDayShort(day, now: now)}, ${selected!.label}',
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

/// Shown when there is nothing to book: the page was opened without a
/// package (the bare /schedule route), or the package can't be paid for.
/// Offers a way back to the packages, like "Your sessions" with no sessions.
class _NoPackage extends StatelessWidget {
  const _NoPackage();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      message: 'Choose a package first, then pick a time for your session.',
      action: OutlinedButton(
        onPressed: () => HomePage.showPackages(context),
        child: const Text('See packages'),
      ),
    );
  }
}
