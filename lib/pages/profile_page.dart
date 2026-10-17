import 'dart:developer';

import 'package:brookie_babies/components/booking_card.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/account_avatar.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';

/// A list of sessions reads best as one column, narrower than the page.
const _pageWidth = 720.0;

/// "Your sessions": the signed-in family's account, their upcoming and past
/// sessions, and photo downloads.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppServices.of(context).auth;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      appBar: AppBar(
        // The design system's arrow on every platform, not the iOS chevron
        // Flutter picks for Macs and iPhones.
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Text('Your sessions'),
      ),
      body: StreamBuilder<AppUser?>(
        stream: auth.authStateChanges,
        initialData: auth.currentUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          final gap = BrookieLayout.sectionGap(context);
          return SingleChildScrollView(
            padding: EdgeInsets.only(top: gap, bottom: gap),
            child: ContentWidth(
              maxWidth: _pageWidth,
              child: user == null ? const _SignedOut() : _Sessions(user: user),
            ),
          );
        },
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text('Your sessions', style: Theme.of(context).textTheme.headlineLarge),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Headline(),
        const SizedBox(height: BrookieSpace.s4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
          child: Text(
            'Sign in to see your sessions and download your photos.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: BrookieSpace.s5),
        FilledButton(
          onPressed: () => showSignInDialog(context),
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}

class _Sessions extends StatefulWidget {
  const _Sessions({required this.user});

  final AppUser user;

  @override
  State<_Sessions> createState() => _SessionsState();
}

class _SessionsState extends State<_Sessions> {
  late Stream<UserBookings> _bookings;

  @override
  void initState() {
    super.initState();
    _bookings = AppServices.of(context).bookings.watchBookings(widget.user.uid);
  }

  @override
  void didUpdateWidget(_Sessions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _bookings = AppServices.of(context).bookings.watchBookings(widget.user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Headline(),
        const SizedBox(height: BrookieSpace.s6),
        _AccountHeader(user: widget.user),
        SizedBox(height: BrookieLayout.sectionGap(context)),
        StreamBuilder<UserBookings>(
          stream: _bookings,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              log('Loading bookings failed: ${snapshot.error}');
              return const InlineMessage(
                  message: "We couldn't load your sessions. Refresh the page to try again.");
            }
            final data = snapshot.data;
            if (data == null) {
              return const Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return _BookingSections(bookings: data.bookings, unreadable: data.unreadable);
          },
        ),
      ],
    );
  }
}

/// Who is signed in, with a way to sign out. On a phone too narrow for both
/// side by side, the button goes below.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final name = user.displayName?.trim() ?? '';
    final email = user.email;
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      spacing: BrookieSpace.s4,
      overflowSpacing: BrookieSpace.s4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AccountAvatar(user: user, size: 56),
            const SizedBox(width: BrookieSpace.s4),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty) Text(name, style: Theme.of(context).textTheme.titleLarge),
                  if (email != null) Text(email, style: TextStyle(color: c.inkSoft)),
                ],
              ),
            ),
          ],
        ),
        OutlinedButton(
          onPressed: AppServices.of(context).auth.signOut,
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _BookingSections extends StatelessWidget {
  const _BookingSections({required this.bookings, required this.unreadable});

  final List<Booking> bookings;
  final int unreadable;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = bookings.where((b) => !b.isPast(now)).toList()
      ..sort((a, b) => a.compareTo(b));
    final past = bookings.where((b) => b.isPast(now)).toList()
      ..sort((a, b) => b.compareTo(a));
    final sectionGap = BrookieLayout.sectionGap(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unreadable > 0) ...[
          const InlineMessage(
              message: "Some of your sessions couldn't be shown. Contact us and "
                  "we'll sort it out."),
          const SizedBox(height: BrookieSpace.s6),
        ],
        if (bookings.isEmpty && unreadable == 0) const _NoSessions(),
        if (upcoming.isNotEmpty)
          _Section(title: 'Upcoming', bookings: upcoming, isPast: false),
        if (upcoming.isNotEmpty && past.isNotEmpty) SizedBox(height: sectionGap),
        if (past.isNotEmpty) _Section(title: 'Past', bookings: past, isPast: true),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.bookings, required this.isPast});

  final String title;
  final List<Booking> bookings;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: BrookieSpace.s4),
        for (final (i, booking) in bookings.indexed) ...[
          if (i > 0) const SizedBox(height: BrookieSpace.s4),
          // Keyed so a card's download state stays with its booking when the
          // list changes.
          BookingCard(key: ValueKey(booking.id), booking: booking, isPast: isPast),
        ],
      ],
    );
  }
}

/// Bookings appear once confirmed, which can lag behind payment.
class _NoSessions extends StatelessWidget {
  const _NoSessions();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrookieColors.of(context).surfaceSunk,
        borderRadius: BorderRadius.circular(BrookieRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BrookieSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No sessions to show yet. After you book, your session appears '
              'here once we’ve confirmed it.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: BrookieSpace.s4),
            OutlinedButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('See packages'),
            ),
          ],
        ),
      ),
    );
  }
}
