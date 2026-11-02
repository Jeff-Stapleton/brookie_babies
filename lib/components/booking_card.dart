import 'package:brookie_babies/components/admin_frame.dart' show breakableEmail;
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/keyboard_input.dart';
import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:brookie_babies/utilities/screen_awake.dart';
import 'package:brookie_babies/utilities/site_domain.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/booking_status_tag.dart';
import 'package:brookie_babies/widgets/brookie_dialog.dart';
import 'package:brookie_babies/widgets/busy_button.dart';
import 'package:brookie_babies/widgets/detail_line.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One session on the "Your sessions" page: its title (an ad hoc session's
/// name, with its package below), payment status, date, time and place, and
/// for sessions whose photos can be delivered (paid or ad hoc), the photo
/// download: the zip's progress while it's built, and a message once the
/// browser has it (or, once past, a note that the photos are being edited).
/// The family's own such sessions can be shared from here; one shared with
/// them says so.
class BookingCard extends StatelessWidget {
  const BookingCard({
    super.key,
    required this.booking,
    required this.isPast,
    this.primaryDownload = true,
    this.sharedWithYou = false,
  });

  final Booking booking;
  final bool isPast;

  /// Whether "Download all photos" is the page's primary (ink) button. The
  /// page has one: on the newest session with photos ready. Others are
  /// outlined.
  final bool primaryDownload;

  /// Whether the family sees it only because its owner shared it with them
  /// (UserBookings.sharedWithUser): it isn't theirs to share.
  final bool sharedWithYou;

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
            if (sharedWithYou) ...[
              const SizedBox(height: BrookieSpace.s2),
              const DetailLine(icon: Icons.people_outline, text: 'Shared with you'),
            ],
            // The photographer decides when photos are ready, so a ready
            // download shows even before the session date (e.g. a sneak peek).
            if (booking.canDeliverPhotos && (booking.photosReady || isPast)) ...[
              const SizedBox(height: BrookieSpace.s5),
              const Divider(),
              const SizedBox(height: BrookieSpace.s5),
              _PhotoDownload(booking: booking, primary: primaryDownload),
            ],
            // Shared before the photos are ready, it's there for whoever it's
            // shared with when they are.
            if (booking.canDeliverPhotos && !sharedWithYou) ...[
              const SizedBox(height: BrookieSpace.s5),
              const Divider(),
              const SizedBox(height: BrookieSpace.s5),
              _Sharing(booking: booking),
            ],
          ],
        ),
      ),
    );
  }
}

/// Who the family's own session is shared with, a way to stop sharing with
/// each, and "Share this session".
class _Sharing extends StatefulWidget {
  const _Sharing({required this.booking});

  final Booking booking;

  @override
  State<_Sharing> createState() => _SharingState();
}

class _SharingState extends State<_Sharing> {
  final _shareFocus = FocusNode(debugLabel: 'Share this session');
  final _stopFocus = <String, FocusNode>{};

  /// The emails being taken off, while that saves.
  final _stopping = <String>{};
  String? _error;

  @override
  void dispose() {
    _shareFocus.dispose();
    for (final node in _stopFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _focusFor(String email) =>
      _stopFocus.putIfAbsent(email, () => FocusNode(debugLabel: 'Stop sharing with $email'));

  Future<void> _share() async {
    setState(() => _error = null);
    await showBrookieDialog<void>(context, builder: (context) => _ShareDialog(booking: widget.booking));
  }

  Future<void> _stopSharing(String email) async {
    if (_stopping.contains(email)) return;
    final confirmed = await showBrookieConfirm(
      context,
      title: 'Stop sharing?',
      message: '$email won’t see this session or be able to download its photos any more.',
      confirmLabel: 'Stop sharing',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    // Its row goes as soon as the change is made here, before the server
    // has it: focus moves on rather than to the top of the page. (Focus
    // only comes back to the button as the confirmation closes.)
    final node = _focusFor(email);
    if (node.hasFocus || FocusScope.of(context).focusedChild == node) _shareFocus.requestFocus();
    setState(() {
      _stopping.add(email);
      _error = null;
    });
    try {
      await AppServices.of(context).bookings.stopSharing(widget.booking, email);
    } on SharingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _stopping.remove(email));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final shared = widget.booking.sharedWith;
    final full = shared.length >= SessionRules.emailListMaxLength;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shared.isEmpty)
          Text('Share it with family, so they can download the photos too.', style: TextStyle(color: c.inkSoft))
        else ...[
          Semantics(header: true, child: Text('Shared with', style: Theme.of(context).textTheme.titleSmall)),
          const SizedBox(height: BrookieSpace.s1),
          for (final email in shared)
            // One node, so the button is heard with whose it is.
            MergeSemantics(
              child: Row(
                children: [
                  Expanded(child: Text(breakableEmail(email), semanticsLabel: email)),
                  const SizedBox(width: BrookieSpace.s3),
                  BusyButton(
                    kind: BusyButtonKind.text,
                    label: 'Stop sharing',
                    busyLabel: 'Stopping…',
                    busy: _stopping.contains(email),
                    focusNode: _focusFor(email),
                    onPressed: () => _stopSharing(email),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: BrookieSpace.s3),
        OutlinedButton.icon(
          focusNode: _shareFocus,
          onPressed: full ? null : _share,
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Share this session'),
        ),
        if (full) ...[
          const SizedBox(height: BrookieSpace.s2),
          Text(
            'It’s shared with ${SessionRules.emailListMaxLength} people, the most it can be. Stop sharing with '
            'someone to add another.',
            style: BrookieType.small.copyWith(color: c.inkSoft),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: BrookieSpace.s3),
          Semantics(container: true, child: InlineMessage(message: error)),
        ],
      ],
    );
  }
}

/// The message to send someone a session was shared with, as [email]:
/// where to go, and which account to sign in with. The site doesn't email
/// them itself.
String sharedSessionMessage(String email) =>
    'I’ve shared a photo session from Brooke Stapleton Photography with you. To see it and download the photos, '
    'open $sessionsLink and sign in with Google as $email.';

/// "Share this session": the email of who to share it with, then, once it's
/// shared, the message to send them.
class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.booking});

  final Booking booking;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final _email = TextEditingController();
  bool _triedToShare = false;
  bool _sharing = false;

  /// What's wrong with the email, once they've tried to share.
  String? _problem;

  /// Why sharing failed.
  String? _error;

  /// Who it was shared with, once it is.
  String? _sharedWith;
  bool _copied = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String? _check() {
    final email = SessionRules.normalizeEmail(_email.text);
    final yours = SessionRules.normalizeEmail(AppServices.of(context).auth.currentUser?.email ?? '');
    if (email.isNotEmpty && email == yours) {
      return 'That’s your own email. Enter the email of the person you’re sharing it with.';
    }
    return sharingProblem(widget.booking, email);
  }

  // The button stays enabled while sharing (BusyButton), so keyboard focus
  // stays on it; another press does nothing.
  Future<void> _share() async {
    if (_sharing) return;
    final problem = _check();
    setState(() {
      _triedToShare = true;
      _problem = problem;
      _error = null;
    });
    if (problem != null) return;
    final email = SessionRules.normalizeEmail(_email.text);
    setState(() => _sharing = true);
    try {
      await AppServices.of(context).bookings.share(widget.booking, email);
      if (mounted) setState(() => _sharedWith = email);
    } on SharingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _copy(String message) async {
    try {
      await Clipboard.setData(ClipboardData(text: message));
    } on PlatformException {
      return; // The browser refused; the message can still be selected and copied.
    }
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final sharedWith = _sharedWith;
    if (sharedWith != null) {
      final message = sharedSessionMessage(sharedWith);
      return BrookieDialog(
        title: 'Let them know',
        content: [
          Text('$sharedWith can now see this session. The site doesn’t email them, so send them this message:'),
          const SizedBox(height: BrookieSpace.s4),
          DecoratedBox(
            decoration: BoxDecoration(color: c.surfaceSunk, borderRadius: BorderRadius.circular(BrookieRadius.sm)),
            child: Padding(
              padding: const EdgeInsets.all(BrookieSpace.s4),
              child: SelectableText(message, style: BrookieType.ui.copyWith(color: c.ink)),
            ),
          ),
        ],
        dismissLabel: 'Done',
        // Rebuilt when the family switches between keyboard and mouse, so the
        // ring follows, like the browser's :focus-visible.
        action: ValueListenableBuilder<bool>(
          valueListenable: KeyboardInput.changes,
          builder: (context, lastWasKey, child) => MergeSemantics(
            // A live region, so screen readers hear "Message copied".
            child: Semantics(
              liveRegion: true,
              child: FilledButton.icon(
                autofocus: true,
                style: brookieDialogPrimaryStyle(context),
                onPressed: () => _copy(message),
                icon: Icon(_copied ? Icons.check : Icons.content_copy_outlined),
                label: Text(_copied ? 'Message copied' : 'Copy message'),
              ),
            ),
          ),
        ),
      );
    }
    final error = _error;
    return BrookieDialog(
      title: 'Share this session',
      content: [
        const Text('They’ll see it under Your sessions and can download its photos. Enter the email they use to '
            'sign in to Google.'),
        const SizedBox(height: BrookieSpace.s4),
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: 'Email',
            errorText: _problem,
            errorMaxLines: 3,
            // The danger edge for a field that's both focused and wrong,
            // which the theme leaves to Material's underline.
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BrookieRadius.sm),
              borderSide: BorderSide(color: c.danger, width: 2),
            ),
          ),
          onChanged: (_) {
            if (_triedToShare) setState(() => _problem = _check());
          },
          onSubmitted: (_) => _share(),
        ),
        if (error != null) ...[
          const SizedBox(height: BrookieSpace.s4),
          InlineMessage(message: error),
        ],
      ],
      dismissLabel: 'Cancel',
      action: BusyButton(
        kind: BusyButtonKind.filled,
        label: 'Share',
        busyLabel: 'Sharing…',
        busy: _sharing,
        onPressed: _share,
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
