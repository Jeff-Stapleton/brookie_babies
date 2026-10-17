import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/widgets/header_four_text.dart';
import 'package:flutter/material.dart';

/// One session on the "My sessions" page: package, date, time and place, and
/// for paid sessions, the photo download (or, once past, a note that the
/// photos are being edited).
class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, required this.isPast});

  final Booking booking;
  final bool isPast;

  static const _statusLabels = {
    BookingStatus.pending: 'Payment pending',
    BookingStatus.cancelled: 'Cancelled',
    BookingStatus.refunded: 'Refunded',
  };

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final time = booking.time;
    final statusLabel = _statusLabels[booking.status];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: HeaderFourText(text: '${booking.packageName} session')),
                if (statusLabel != null) Chip(label: Text(statusLabel)),
              ],
            ),
            const SizedBox(height: 8),
            _Detail(icon: Icons.event, text: localizations.formatFullDate(booking.date)),
            if (time != null)
              _Detail(
                icon: Icons.schedule,
                text: localizations.formatTimeOfDay(TimeOfDay(hour: time.hour, minute: time.minute)),
              ),
            if (booking.location != null) _Detail(icon: Icons.place, text: booking.location!),
            // The photographer decides when photos are ready, so a ready
            // download shows even before the session date (e.g. a sneak peek).
            if (booking.status == BookingStatus.paid && (booking.photosReady || isPast)) ...[
              const SizedBox(height: 16),
              _PhotoDownload(booking: booking),
            ],
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
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
    if (!widget.booking.photosReady) {
      return const Text(
          "Your photos are being edited. They'll be ready to download here soon.");
    }
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: _preparing ? null : _download,
          icon: _preparing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
          label: Text(_preparing ? 'Preparing your photos…' : 'Download all photos'),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }
}
