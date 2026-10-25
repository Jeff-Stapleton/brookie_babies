import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/booking_status_tag.dart';
import 'package:brookie_babies/widgets/detail_line.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';

/// One session on the "Your sessions" page: its title (an ad hoc session's
/// name, with its package below), payment status, date, time and place, and
/// for sessions whose photos can be delivered (paid or ad hoc), the photo
/// download (or, once past, a note that the photos are being edited).
class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, required this.isPast, this.primaryDownload = true});

  final Booking booking;
  final bool isPast;

  /// Whether "Download all photos" is the page's primary (ink) button. The
  /// page has one: on the newest session with photos ready. Others are
  /// outlined.
  final bool primaryDownload;

  @override
  Widget build(BuildContext context) {
    final time = booking.time;
    final location = booking.location;
    final title = booking.familyTitle;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(BrookieSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The tag sits at the right of the title, or below it when the
            // card is too narrow for both. Full width so spaceBetween has
            // room to push the tag right.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: BrookieSpace.s3,
                runSpacing: BrookieSpace.s2,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  // Nothing was bought, so there's no payment to report.
                  if (!booking.isAdHoc) BookingStatusTag(status: booking.status),
                ],
              ),
            ),
            // Under an ad hoc session's name, its package, as on its admin card.
            if (title != booking.title) ...[
              const SizedBox(height: BrookieSpace.s1),
              Text(booking.title, style: TextStyle(color: BrookieColors.of(context).inkSoft)),
            ],
            const SizedBox(height: BrookieSpace.s3),
            DetailLine(icon: Icons.event_outlined, text: formatDayShort(booking.date, now: DateTime.now())),
            // The start time only: a booking doesn't record how long it runs.
            if (time != null) ...[
              const SizedBox(height: BrookieSpace.s2),
              DetailLine(icon: Icons.schedule_outlined, text: SessionTime.clockLabel(time.hour, time.minute)),
            ],
            if (location != null) ...[
              const SizedBox(height: BrookieSpace.s2),
              DetailLine(icon: Icons.place_outlined, text: location),
            ],
            // The photographer decides when photos are ready, so a ready
            // download shows even before the session date (e.g. a sneak peek).
            if (booking.canDeliverPhotos && (booking.photosReady || isPast)) ...[
              const SizedBox(height: BrookieSpace.s5),
              const Divider(),
              const SizedBox(height: BrookieSpace.s5),
              _PhotoDownload(booking: booking, primary: primaryDownload),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoDownload extends StatefulWidget {
  const _PhotoDownload({required this.booking, required this.primary});

  final Booking booking;
  final bool primary;

  @override
  State<_PhotoDownload> createState() => _PhotoDownloadState();
}

class _PhotoDownloadState extends State<_PhotoDownload> {
  bool _preparing = false;
  String? _error;

  // The button stays enabled while the zip is prepared: a disabled button
  // drops keyboard focus (onto "Sign out", where a second Enter would sign
  // the family out). Another press just waits for the same download.
  Future<void> _download() async {
    if (_preparing) return;
    final services = AppServices.of(context);
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final download = await services.gallery.prepareDownload(widget.booking.id);
      // Gone means signed out or left the page; don't start their download.
      if (!mounted) return;
      // Same tab: the link is a file download, so the page stays put, and a
      // new tab opened this long after the tap would be blocked as a popup.
      await services.openUrl(download.url, webOnlyWindowName: '_self');
    } on GalleryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  /// While preparing, the button looks disabled (surface-sunk, ink-soft)
  /// but keeps focus. Focus keeps the theme's ring (the outlined one keeps
  /// its edge inside it).
  ButtonStyle? _busyStyle(BrookieColors c) {
    if (!_preparing) return null;
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(widget.primary ? c.surfaceSunk : Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(c.inkSoft),
      iconColor: WidgetStatePropertyAll(c.inkSoft),
      side: widget.primary ? null : WidgetStatePropertyAll(BorderSide(color: c.line, width: 1.5)),
      mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.progress),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    if (!widget.booking.photosReady) {
      return Text(
        'Your photos are being edited. They’ll be ready to download here soon.',
        style: TextStyle(color: c.inkSoft),
      );
    }
    final error = _error;
    final icon = _preparing
        ? SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.inkSoft),
          )
        : const Icon(Icons.download_outlined);
    final label = Text(_preparing ? 'Preparing your photos…' : 'Download all photos');
    final style = _busyStyle(c);
    final button = widget.primary
        ? FilledButton.icon(onPressed: _download, style: style, icon: icon, label: label)
        : OutlinedButton.icon(onPressed: _download, style: style, icon: icon, label: label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StatusTag(label: 'Ready to download', tone: StatusTone.success),
        const SizedBox(height: BrookieSpace.s3),
        // One node and a live region, so screen readers hear "Preparing your
        // photos…" and then the button's name again.
        MergeSemantics(child: Semantics(liveRegion: true, child: button)),
        if (error != null) ...[
          const SizedBox(height: BrookieSpace.s3),
          InlineMessage(message: error),
        ],
      ],
    );
  }
}
