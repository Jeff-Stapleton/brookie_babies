import 'package:brookie_babies/components/admin_frame.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/booking_status_tag.dart';
import 'package:brookie_babies/widgets/detail_line.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';

/// Who a session is for, as the admin pages name it: the name given to an
/// ad hoc session, else the booking's email.
String sessionDisplayName(Booking booking) => booking.name ?? booking.email ?? 'Session';

/// Whether the family can download a session's photos, as a tag: "Ready
/// to download" or "Not ready".
class PhotosReadyTag extends StatelessWidget {
  const PhotosReadyTag({super.key, required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    return ready
        ? const StatusTag(label: 'Ready to download', tone: StatusTone.success)
        : const StatusTag(label: 'Not ready');
  }
}

/// One session in the admin page's list: who it's for, the package, the
/// day and time, how it was paid for and whether its photos are ready. The
/// whole card opens the session ([onOpen]), by click, tap, Enter or Space.
class AdminSessionCard extends StatefulWidget {
  const AdminSessionCard({super.key, required this.booking, required this.now, required this.onOpen});

  final Booking booking;

  /// Today, so a day in another year shows its year.
  final DateTime now;

  final VoidCallback onOpen;

  @override
  State<AdminSessionCard> createState() => _AdminSessionCardState();
}

class _AdminSessionCardState extends State<AdminSessionCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final booking = widget.booking;
    final time = booking.time;
    final open = CallbackAction<Intent>(onInvoke: (_) {
      widget.onOpen();
      return null;
    });
    // One node: everything the card says, as a button.
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          // Space activates it everywhere; on the web, Enter only activates
          // buttons (ButtonActivateIntent), which this is.
          actions: {ActivateIntent: open, ButtonActivateIntent: open},
          child: GestureDetector(
            onTap: widget.onOpen,
            behavior: HitTestBehavior.opaque,
            child: FocusRing(
              visible: _focused,
              borderRadius: BrookieRadius.md,
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : kBrookieStateDuration,
                padding: const EdgeInsets.all(BrookieSpace.s5),
                decoration: BoxDecoration(
                  color: c.surface,
                  // Hover darkens the edge, as it does a session slot's.
                  border: Border.all(color: _hovered ? c.lineStrong : c.line),
                  borderRadius: BorderRadius.circular(BrookieRadius.md),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            breakableEmail(sessionDisplayName(booking)),
                            semanticsLabel: sessionDisplayName(booking),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: BrookieSpace.s1),
                          Text(booking.title, style: TextStyle(color: c.inkSoft)),
                          const SizedBox(height: BrookieSpace.s3),
                          DetailLine(icon: Icons.event_outlined, text: formatDayShort(booking.date, now: widget.now)),
                          if (time != null) ...[
                            const SizedBox(height: BrookieSpace.s2),
                            DetailLine(
                              icon: Icons.schedule_outlined,
                              text: SessionTime.clockLabel(time.hour, time.minute),
                            ),
                          ],
                          const SizedBox(height: BrookieSpace.s3),
                          Wrap(
                            spacing: BrookieSpace.s2,
                            runSpacing: BrookieSpace.s2,
                            children: [
                              BookingStatusTag(status: booking.status),
                              PhotosReadyTag(ready: booking.photosReady),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: BrookieSpace.s3),
                    Icon(Icons.chevron_right, color: c.inkSoft),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
