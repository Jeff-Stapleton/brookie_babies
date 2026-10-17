import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';

/// One session on the "Your sessions" page: package, payment status, date,
/// time and place, and for paid sessions, the photo download (or, once past,
/// a note that the photos are being edited).
class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, required this.isPast});

  final Booking booking;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final time = booking.time;
    final location = booking.location;
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
                  Text('${booking.packageName} session', style: Theme.of(context).textTheme.titleLarge),
                  _PaymentTag(status: booking.status),
                ],
              ),
            ),
            const SizedBox(height: BrookieSpace.s3),
            _Detail(icon: Icons.event_outlined, text: _formatDate(booking.date, DateTime.now())),
            if (time != null) ...[
              const SizedBox(height: BrookieSpace.s2),
              _Detail(icon: Icons.schedule_outlined, text: _formatTime(time.hour, time.minute)),
            ],
            if (location != null) ...[
              const SizedBox(height: BrookieSpace.s2),
              _Detail(icon: Icons.place_outlined, text: location),
            ],
            // The photographer decides when photos are ready, so a ready
            // download shows even before the session date (e.g. a sneak peek).
            if (booking.status == BookingStatus.paid && (booking.photosReady || isPast)) ...[
              const SizedBox(height: BrookieSpace.s5),
              const Divider(),
              const SizedBox(height: BrookieSpace.s5),
              _PhotoDownload(booking: booking),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentTag extends StatelessWidget {
  const _PaymentTag({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      BookingStatus.paid => const StatusTag(label: 'Paid', tone: StatusTone.success, icon: Icons.check),
      BookingStatus.pending => const StatusTag(label: 'Payment pending'),
      BookingStatus.cancelled => const StatusTag(label: 'Cancelled'),
      BookingStatus.refunded => const StatusTag(label: 'Refunded'),
    };
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Sat, Oct 24", with the year added when it isn't [now]'s: "Sun, May 6, 2001".
String _formatDate(DateTime date, DateTime now) {
  final day = '${_weekdays[date.weekday - DateTime.monday]}, ${_months[date.month - 1]} ${date.day}';
  return date.year == now.year ? day : '$day, ${date.year}';
}

/// "9:00 am", "2:30 pm", "12:00 pm".
String _formatTime(int hour, int minute) {
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'am' : 'pm'}';
}

/// One line of the session's details, labelled by an icon.
class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Centers the 20px icon on the text's 22px first line.
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 20, color: BrookieColors.of(context).inkSoft),
        ),
        const SizedBox(width: BrookieSpace.s2),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _PhotoDownload extends StatefulWidget {
  const _PhotoDownload({required this.booking});

  final Booking booking;

  @override
  State<_PhotoDownload> createState() => _PhotoDownloadState();
}

class _PhotoDownloadState extends State<_PhotoDownload> {
  bool _preparing = false;
  String? _error;

  Future<void> _download() async {
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

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    if (!widget.booking.photosReady) {
      return Text(
        "Your photos are being edited. They'll be ready to download here soon.",
        style: TextStyle(color: c.inkSoft),
      );
    }
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StatusTag(label: 'Ready to download', tone: StatusTone.success),
        const SizedBox(height: BrookieSpace.s3),
        FilledButton.icon(
          onPressed: _preparing ? null : _download,
          icon: _preparing
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c.inkSoft),
                )
              : const Icon(Icons.download_outlined),
          label: Text(_preparing ? 'Preparing your photos…' : 'Download all photos'),
        ),
        if (error != null) ...[
          const SizedBox(height: BrookieSpace.s3),
          InlineMessage(message: error),
        ],
      ],
    );
  }
}
