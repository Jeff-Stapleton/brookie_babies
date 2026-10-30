import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:brookie_babies/utilities/screen_awake.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/booking_status_tag.dart';
import 'package:brookie_babies/widgets/busy_button.dart';
import 'package:brookie_babies/widgets/detail_line.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';

/// One session on the "Your sessions" page: its title (an ad hoc session's
/// name, with its package below), payment status, date, time and place, and
/// for sessions whose photos can be delivered (paid or ad hoc), the photo
/// download: the zip's progress while it's built, and a message once the
/// browser has it (or, once past, a note that the photos are being edited).
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

/// "Download all photos": a busy button while the zip is prepared, with
/// its progress below once the server starts building it (which photo, a
/// bar, the size), then a success or error message.
class _PhotoDownload extends StatefulWidget {
  const _PhotoDownload({required this.booking, required this.primary});

  final Booking booking;
  final bool primary;

  @override
  State<_PhotoDownload> createState() => _PhotoDownloadState();
}

/// The download being prepared on this page, if any. One at a time: handing
/// a zip to the browser is a same-tab navigation, which asks "Leave site?"
/// while another card has its warning on, and in Safari and Firefox stops
/// the page's other requests, so a second preparation would be lost.
_PhotoDownloadState? _preparingDownload;

class _PhotoDownloadState extends State<_PhotoDownload> {
  bool _preparing = false;

  /// Pressed while another card was preparing ([_preparingDownload]).
  bool _waitingForOther = false;

  /// How the zip's build is going; null until the first chunk, and for a
  /// zip that's already built.
  GalleryProgress? _progress;

  /// The download last handed to the browser, for the success message.
  GalleryDownload? _started;

  String? _error;

  /// Whether the page was hidden while the zip was prepared, which can
  /// explain a failure the function didn't.
  bool _hiddenWhilePreparing = false;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Hidden (another tab or app, a locked phone), not merely unfocused
    // (that's `inactive`): phones drop the connection then, and the download
    // can't start by itself.
    _lifecycle = AppLifecycleListener(onHide: () {
      if (_preparing) _hiddenWhilePreparing = true;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _waiting(false);
    super.dispose();
  }

  /// Leaving would lose the automatic start, and a locked phone drops the
  /// connection. No PopScope: leaving for another page of the site keeps the
  /// request going, so the zip is still built and cached. Also holds the
  /// page's one preparation ([_preparingDownload]).
  void _waiting(bool on) {
    LeaveWarning.set(this, on);
    ScreenAwake.set(this, on);
    if (on) {
      _preparingDownload = this;
    } else if (identical(_preparingDownload, this)) {
      _preparingDownload = null;
    }
  }

  Future<void> _download() async {
    if (_preparing) return;
    if (_preparingDownload != null) {
      setState(() {
        _waitingForOther = true;
        _started = null;
        _error = null;
      });
      return;
    }
    final services = AppServices.of(context);
    setState(() {
      _preparing = true;
      _waitingForOther = false;
      _progress = null;
      _started = null;
      _error = null;
      _hiddenWhilePreparing = false;
    });
    // Before any await, so main.dart asks for the screen lock inside the tap.
    _waiting(true);
    try {
      final download = await services.gallery.prepareDownload(
        widget.booking.id,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      // Gone means signed out or left the page; don't start their download.
      if (!mounted) return;
      // Off first: a same-tab navigation fires beforeunload, so the download
      // itself would ask "Leave site?". (No other card is preparing: see
      // [_preparingDownload].)
      _waiting(false);
      // Same tab: the link is a file download, so the page stays put, and a
      // new tab opened this long after the tap would be blocked as a popup.
      final opened = await services.openUrl(download.url, webOnlyWindowName: '_self');
      if (opened && mounted) setState(() => _started = download);
    } on GalleryException catch (e) {
      if (mounted) {
        setState(() => _error = e.isFallback && _hiddenWhilePreparing ? kDownloadInterruptedMessage : e.message);
      }
    } finally {
      _waiting(false);
      if (mounted) {
        setState(() {
          _preparing = false;
          _progress = null;
        });
      }
    }
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
    final progress = _progress;
    final started = _started;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StatusTag(label: 'Ready to download', tone: StatusTone.success),
        const SizedBox(height: BrookieSpace.s3),
        // Keeps keyboard focus while busy (a disabled button would drop it
        // onto "Sign out", where a second Enter would sign the family out);
        // another press just waits for the same download.
        BusyButton(
          kind: widget.primary ? BusyButtonKind.filled : BusyButtonKind.outlined,
          icon: Icons.download_outlined,
          label: 'Download all photos',
          busyLabel: _preparingLabel,
          busySemanticsLabel: progress == null ? null : zipProgressAnnouncement(progress),
          busy: _preparing,
          onPressed: _download,
        ),
        if (_preparing && progress != null) ...[
          const SizedBox(height: BrookieSpace.s3),
          _ZipProgress(progress: progress),
        ],
        // Each message its own node, so its live region announces just the
        // message, not the whole card it would otherwise merge into.
        if (started != null) ...[
          const SizedBox(height: BrookieSpace.s3),
          Semantics(
            container: true,
            child: InlineMessage(message: downloadStartedMessage(started), tone: StatusTone.success),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: BrookieSpace.s3),
          Semantics(container: true, child: InlineMessage(message: error)),
        ],
        if (_waitingForOther) ...[
          const SizedBox(height: BrookieSpace.s3),
          Semantics(
            container: true,
            child: InlineMessage(message: kOneDownloadAtATimeMessage, tone: StatusTone.neutral),
          ),
        ],
      ],
    );
  }
}

/// How the zip's build is going: which photo, a bar by photos, and how
/// long it may take. Its line and bar match the admin's uploads.
///
/// Only the hint is a live region, and it doesn't change during a build, so
/// it's heard once, when the panel appears; the busy button announces the
/// quarters. Each part is its own node: merged into the card, the hint
/// would make the whole card a live region that changed at every photo.
class _ZipProgress extends StatelessWidget {
  const _ZipProgress({required this.progress});

  final GalleryProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final p = progress;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(zipProgressLine(p), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: BrookieSpace.s1),
          // Ink on surface-sunk, from the theme. Determinate, so it doesn't
          // animate.
          LinearProgressIndicator(
            value: p.fraction,
            minHeight: BrookieSpace.s1,
            borderRadius: BorderRadius.circular(BrookieSpace.s1 / 2),
            semanticsLabel: 'Photos added',
            // A progress bar's value must be a number or a percentage; the
            // line above has the count.
            semanticsValue: '${(p.fraction * 100).round()}%',
          ),
          const SizedBox(height: BrookieSpace.s2),
          Semantics(
            liveRegion: true,
            child: Text(zipProgressHint(p), style: BrookieType.ui.copyWith(color: c.inkSoft)),
          ),
        ],
      ),
    );
  }
}

/// What the busy button says, and the start of what screen readers hear.
const _preparingLabel = 'Preparing your photos…';

/// While the page was hidden and the wait failed for no stated reason. A
/// phone drops the connection then; a computer doesn't, so the cause is
/// hedged and the next step is the generic one's.
const kDownloadInterruptedMessage =
    'We couldn’t get your photos ready, perhaps because this page was in the background. Choose '
    '“Download all photos” again and keep this page on screen until it starts. If it happens again, '
    'let Brooke know.';

/// Pressed while another session's photos are being prepared.
const kOneDownloadAtATimeMessage =
    'Photos from another session are being prepared. Once that download starts, choose “Download all '
    'photos” here.';

String _photos(int n) => n == 1 ? '1 photo' : '$n photos';

/// "Adding photo 38 of 150"; "Adding your photo" for one; "Finishing your
/// zip file" once all are in.
String zipProgressLine(GalleryProgress p) {
  if (p.finishing) return 'Finishing your zip file';
  if (p.photoCount == 1) return 'Adding your photo';
  return 'Adding photo ${p.photosDone + 1} of ${p.photoCount}';
}

/// "This can take a few minutes. Your 4.8 GB zip file starts downloading by
/// itself when it’s ready, so keep this page open and on screen." (A phone
/// drops the wait when another app takes the screen.) Without totalBytes:
/// "…Your zip file starts…".
String zipProgressHint(GalleryProgress p) {
  final size = p.totalBytes;
  final zip = size == null ? 'Your zip file' : 'Your ${formatFileSize(size)} zip file';
  return 'This can take a few minutes. $zip starts downloading by itself when it’s ready, so keep this page '
      'open and on screen.';
}

/// The busy button's spoken label: null (so "Preparing your photos…") below
/// 25%; "Preparing your photos… 25% done" / "50%" / "75%"; "Preparing your
/// photos… finishing up". A long build is announced a few times, not at
/// every photo.
String? zipProgressAnnouncement(GalleryProgress p) {
  if (p.finishing) return '$_preparingLabel finishing up';
  final quarter = (p.fraction * 4).floor().clamp(0, 3);
  return quarter == 0 ? null : '$_preparingLabel ${quarter * 25}% done';
}

/// "Your download has started: 150 photos, 4.8 GB. If your browser asks,
/// allow it; if nothing happens, choose “Download all photos” again."
/// Without totalBytes: "…started: 150 photos. If…".
String downloadStartedMessage(GalleryDownload d) {
  final size = d.totalBytes;
  final what = size == null ? _photos(d.photoCount) : '${_photos(d.photoCount)}, ${formatFileSize(size)}';
  return 'Your download has started: $what. If your browser asks, allow it; if nothing happens, choose '
      '“Download all photos” again.';
}
