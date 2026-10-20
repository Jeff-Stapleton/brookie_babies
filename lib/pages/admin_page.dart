import 'dart:developer';

import 'package:brookie_babies/components/admin_frame.dart';
import 'package:brookie_babies/components/admin_gate.dart';
import 'package:brookie_babies/components/admin_session_card.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_lookup.dart';
import 'package:brookie_babies/pages/admin_session_page.dart';
import 'package:brookie_babies/pages/home_photos_admin_page.dart';
import 'package:brookie_babies/pages/session_form_page.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/empty_state.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// "Admin": the studio's sessions, and the way to the home page photos
/// (route /admin). Admins only ([AdminGate]).
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  /// Also linkable as https://brookie-babies.web.app/#/admin.
  static const routeName = '/admin';

  /// Opens the admin page over the home page, closing anything else that
  /// was open (the account menu's "Admin").
  static void open(BuildContext context) {
    _notice.value = null;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(settings: const RouteSettings(name: routeName), builder: (context) => const AdminPage()),
      (route) => route.isFirst,
    );
  }

  /// Goes back to the admin page and shows [message] there as a success
  /// notice: "Deleted the Harper family’s session."
  static void returnWithNotice(BuildContext context, String message) {
    // Home rather than an empty navigator, should the admin page not be
    // open below.
    Navigator.of(context).popUntil((route) => route.settings.name == routeName || route.isFirst);
    _notice.value = message;
  }

  /// The success notice to show, if any. The admin page shows it until it
  /// is [clearNotice]d, opened again, or closed.
  static ValueListenable<String?> get notice => _notice;

  static void clearNotice() => _notice.value = null;

  static final _notice = ValueNotifier<String?>(null);

  /// How many admin pages are open (briefly two, while one replaces another).
  static var _open = 0;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    AdminPage._open++;
    AdminPage.notice.addListener(_showNotice);
  }

  @override
  void dispose() {
    AdminPage.notice.removeListener(_showNotice);
    _scroll.dispose();
    // A notice is about this visit; the next one starts clean.
    if (--AdminPage._open == 0) AdminPage.clearNotice();
    super.dispose();
  }

  /// A notice arrives as the admin comes back from deep in the list (say,
  /// from a session they deleted), so the page goes back up to show it.
  void _showNotice() {
    if (AdminPage.notice.value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _scroll.offset == 0) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(0, duration: kBrookieFadeDuration, curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrookieTopBar(title: 'Admin', showAdminLink: false),
      body: AdminGate(
        child: AdminFrame(
          controller: _scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminHeading('Admin', page: true),
              ValueListenableBuilder<String?>(
                valueListenable: AdminPage.notice,
                builder: (context, notice, child) => notice == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: BrookieSpace.s5),
                        child: InlineMessage(message: notice, tone: StatusTone.success),
                      ),
              ),
              const SizedBox(height: BrookieSpace.s6),
              const _HomePhotosCard(),
              SizedBox(height: BrookieLayout.sectionGap(context)),
              const _Sessions(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Leaving the admin page for one of its own: the notice was about this
/// visit, and shouldn't greet the admin on the way back.
void _push(BuildContext context, Widget page) {
  AdminPage.clearNotice();
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => page));
}

class _HomePhotosCard extends StatelessWidget {
  const _HomePhotosCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(BrookieSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminHeading('Home page photos'),
            const SizedBox(height: BrookieSpace.s2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
              child: const Text('Choose the photos on the home page, and add new ones to its library.'),
            ),
            const SizedBox(height: BrookieSpace.s4),
            OutlinedButton(
              onPressed: () => _push(context, const HomePhotosAdminPage()),
              child: const Text('Edit home page photos'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Sessions": every booking and ad hoc session, upcoming then past, and
/// any the app couldn't read. Built only once the gate has let an admin in,
/// so nobody else asks Firestore for them.
class _Sessions extends StatefulWidget {
  const _Sessions();

  @override
  State<_Sessions> createState() => _SessionsState();
}

class _SessionsState extends State<_Sessions> {
  late final Stream<AllSessions> _sessions = AppServices.of(context).admin.watchSessions();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The button goes under the title when both don't fit on one line.
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          overflowAlignment: OverflowBarAlignment.start,
          spacing: BrookieSpace.s4,
          overflowSpacing: BrookieSpace.s4,
          children: [
            const AdminHeading('Sessions'),
            FilledButton.icon(
              onPressed: () => _push(context, const SessionFormPage()),
              icon: const Icon(Icons.add),
              label: const Text('Add a session'),
            ),
          ],
        ),
        const SizedBox(height: BrookieSpace.s5),
        StreamBuilder<AllSessions>(
          stream: _sessions,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              log('Loading sessions failed: ${snapshot.error}');
              return const InlineMessage(message: 'We couldn’t load the sessions. Refresh the page to try again.');
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
            return _SessionList(sessions: data.sessions, unreadable: data.unreadable);
          },
        ),
      ],
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.sessions, required this.unreadable});

  final List<Booking> sessions;
  final List<UnreadableBooking> unreadable;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = sessions.where((b) => !b.isPast(now)).toList()..sort((a, b) => a.compareTo(b));
    final past = sessions.where((b) => b.isPast(now)).toList()..sort((a, b) => b.compareTo(a));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unreadable.isNotEmpty) ...[
          _Unreadable(bookings: unreadable),
          const SizedBox(height: BrookieSpace.s6),
        ],
        if (sessions.isEmpty && unreadable.isEmpty)
          const EmptyState(
            message: 'No sessions yet. Sessions booked on the site appear here, and so do ones you add.',
          ),
        if (upcoming.isNotEmpty) _Group(title: 'Upcoming', sessions: upcoming, now: now),
        if (upcoming.isNotEmpty && past.isNotEmpty) const SizedBox(height: BrookieSpace.s6),
        if (past.isNotEmpty) _Group(title: 'Past', sessions: past, now: now),
      ],
    );
  }
}

/// "Upcoming" (soonest first) or "Past" (newest first).
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.sessions, required this.now});

  final String title;
  final List<Booking> sessions;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: BrookieSpace.s3),
        for (final (i, booking) in sessions.indexed) ...[
          if (i > 0) const SizedBox(height: BrookieSpace.s4),
          AdminSessionCard(
            key: ValueKey(booking.id),
            booking: booking,
            now: now,
            onOpen: () => _push(context, AdminSessionPage(sessionId: booking.id)),
          ),
        ],
      ],
    );
  }
}

/// Documents in `bookings` that the app can't read (a typo in one entered
/// by hand), each with its id to find it by in the Firestore console.
class _Unreadable extends StatelessWidget {
  const _Unreadable({required this.bookings});

  final List<UnreadableBooking> bookings;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final count = bookings.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineMessage(
          message: '$count ${count == 1 ? 'session' : 'sessions'} couldn’t be read. '
              '${count == 1 ? 'Fix it' : 'Fix them'} in the Firestore console.',
        ),
        for (final booking in bookings)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(BrookieSpace.s4, BrookieSpace.s3, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selectable, to paste into the console's search.
                SelectableText(booking.id, style: Theme.of(context).textTheme.titleSmall),
                // "date isn’t YYYY-MM-DD": the field, as the console names it.
                Text(booking.problem),
                if (booking.email != null || booking.date != null)
                  Text(
                    [
                      if (booking.email case final email?) email,
                      if (booking.date case final date?) date,
                    ].join(' · '),
                    style: BrookieType.small.copyWith(color: c.inkSoft),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
