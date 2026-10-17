import 'dart:developer';

import 'package:brookie_babies/components/booking_card.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/widgets/header_four_text.dart';
import 'package:brookie_babies/widgets/header_three_text.dart';
import 'package:flutter/material.dart';

/// "My sessions": the signed-in customer's account, their upcoming and past
/// sessions, and photo downloads for past ones.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppServices.of(context).auth;
    return Scaffold(
      appBar: AppBar(title: const Text('My sessions')),
      body: StreamBuilder<AppUser?>(
        stream: auth.authStateChanges,
        initialData: auth.currentUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: user == null ? const _SignedOut() : _Sessions(user: user),
            ),
          );
        },
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Sign in to see your sessions and download your photos.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => showSignInDialog(context),
            icon: const Icon(Icons.login),
            label: const Text('Sign in'),
          ),
        ],
      ),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AccountHeader(user: widget.user),
        const SizedBox(height: 24),
        StreamBuilder<UserBookings>(
          stream: _bookings,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              log('Loading bookings failed: ${snapshot.error}');
              return const Text("We couldn't load your sessions. Please try again later.");
            }
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _BookingSections(bookings: data.bookings, unreadable: data.unreadable);
          },
        ),
      ],
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName;
    final email = user.email;
    return Row(
      children: [
        CircleAvatar(radius: 28, child: Text(user.initial)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name != null && name.isNotEmpty) HeaderFourText(text: name),
              if (email != null) Text(email),
            ],
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unreadable > 0) ...[
          const Text(
              "Some of your sessions couldn't be shown. Please contact us and "
              "we'll sort it out."),
          const SizedBox(height: 16),
        ],
        if (bookings.isEmpty && unreadable == 0) ...[
          // Bookings appear once confirmed, which can lag behind payment.
          const Text(
              'No sessions to show yet. After you book, your session appears '
              "here once we've confirmed it."),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('See packages'),
            ),
          ),
        ],
        if (upcoming.isNotEmpty) ...[
          const HeaderThreeText(text: 'Upcoming'),
          const SizedBox(height: 8),
          // Keyed so a card's download state stays with its booking when the
          // list changes.
          for (final booking in upcoming)
            BookingCard(key: ValueKey(booking.id), booking: booking, isPast: false),
          const SizedBox(height: 24),
        ],
        if (past.isNotEmpty) ...[
          const HeaderThreeText(text: 'Past'),
          const SizedBox(height: 8),
          for (final booking in past)
            BookingCard(key: ValueKey(booking.id), booking: booking, isPast: true),
        ],
      ],
    );
  }
}
