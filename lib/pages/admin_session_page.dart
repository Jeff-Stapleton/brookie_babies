import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:brookie_babies/components/admin_frame.dart';
import 'package:brookie_babies/components/admin_gate.dart';
import 'package:brookie_babies/components/admin_session_card.dart';
import 'package:brookie_babies/components/upload_progress_list.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/session_lookup.dart';
import 'package:brookie_babies/models/session_time.dart';
import 'package:brookie_babies/models/stored_photo.dart';
import 'package:brookie_babies/pages/admin_page.dart';
import 'package:brookie_babies/pages/session_form_page.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:brookie_babies/utilities/upload_queue.dart';
import 'package:brookie_babies/utilities/utils.dart';
import 'package:brookie_babies/widgets/booking_status_tag.dart';
import 'package:brookie_babies/widgets/brookie_dialog.dart';
import 'package:brookie_babies/widgets/busy_button.dart';
import 'package:brookie_babies/widgets/detail_line.dart';
import 'package:brookie_babies/widgets/empty_state.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One session, for admins: its details, who can download its photos and
/// how to tell them, whether they can yet, and the photos themselves, with
/// uploading and deleting. Ad hoc sessions can also be edited and deleted.
///
/// The top bar names who the session is for once it has loaded.
class AdminSessionPage extends StatefulWidget {
  const AdminSessionPage({super.key, required this.sessionId});

  /// The `bookings` document id.
  final String sessionId;

  /// Where families download their photos, on the site this runs on (the
  /// live site when it isn't running on the web).
  static Uri get familyLink {
    final base = Uri.base;
    final origin = base.isScheme('http') || base.isScheme('https') ? base.origin : 'https://brookie-babies.web.app';
    return Uri.parse('$origin/#/profile');
  }

  /// The message to send the family: where to go, and which account to
  /// sign in with.
  static String shareMessage(Booking booking) {
    final email = booking.email;
    // An ad hoc session is shared with its email; a booking with the Google
    // account that paid, whatever email was noted on it.
    final account = booking.isAdHoc && email != null
        ? 'sign in with Google as $email'
        : 'sign in with the Google account you booked with';
    return 'Your photos from Brooke are ready. Open $familyLink and $account to download them.';
  }

  @override
  State<AdminSessionPage> createState() => _AdminSessionPageState();
}

class _AdminSessionPageState extends State<AdminSessionPage> {
  /// Who the session is for, once the body has read it.
  String? _title;

  void _setTitle(String? title) {
    if (mounted && title != _title) setState(() => _title = title);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No "Your sessions" either: its "Admin" and "See packages" would
      // close this page without asking, stopping any uploads.
      appBar: BrookieTopBar(title: _title ?? 'Session', showSessionsLink: false, showAdminLink: false),
      body: AdminGate(child: _SessionBody(sessionId: widget.sessionId, onTitle: _setTitle)),
    );
  }
}

/// "1 photo", "150 photos".
String _photoCount(int count) => '$count ${count == 1 ? 'photo' : 'photos'}';

/// Who can download [booking]'s photos, as the start of a sentence, or null
/// if nobody can: an ad hoc session without an email, or a booking without
/// a uid.
String? _whoCanDownload(Booking booking) {
  if (booking.isAdHoc) {
    final email = booking.email;
    return email == null ? null : 'Anyone signed in with Google as $email';
  }
  final uid = booking.uid;
  return uid == null ? null : 'The Google account with user ID $uid';
}

/// [name] mid-sentence: "The Harper family" becomes "the Harper family".
String _inSentence(String name) => name.startsWith('The ') ? 't${name.substring(1)}' : name;

/// What a failed action says: the service's own message, else [fallback].
String _messageFor(Object error, String fallback) {
  if (error is AdminException) return error.message;
  log('Admin action failed: $error');
  return fallback;
}

/// Where AdminService stores a session's photo (storage.rules:
/// `galleries/{bookingId}/`), for one the page uploaded itself.
StoredPhoto _storedPhoto(String sessionId, String name) =>
    StoredPhoto(name: name, fullPath: 'galleries/$sessionId/$name');

/// The session's page, once AdminGate has let an admin in: it watches the
/// session and lists its photos only then.
class _SessionBody extends StatefulWidget {
  const _SessionBody({required this.sessionId, required this.onTitle});

  final String sessionId;

  /// Reports who the session is for (null when there's no session to
  /// name), for the top bar.
  final ValueChanged<String?> onTitle;

  @override
  State<_SessionBody> createState() => _SessionBodyState();
}

class _SessionBodyState extends State<_SessionBody> {
  late final AdminService _admin = AppServices.of(context).admin;
  late final UploadQueue _queue;
  StreamSubscription<SessionLookup>? _subscription;

  /// Null until the first answer.
  SessionLookup? _lookup;
  SessionFound? _lastFound;
  bool _watchFailed = false;

  /// The session's photos, sorted by name; null until listed.
  List<StoredPhoto>? _photos;
  bool _listing = false;
  bool _listFailed = false;

  /// What the page shows of the queue; it rebuilds only when this changes,
  /// not on every bit of progress (UploadProgressList follows that).
  ({bool busy, int items, int failed, int done})? _queueSummary;

  /// The photosReady being saved; null when not saving.
  bool? _savingReadyTo;
  bool get _savingReady => _savingReadyTo != null;
  String? _readyError;

  /// Photos stored while the others could already be downloaded, by name:
  /// families who already downloaded need to again to get these. Forgotten
  /// when the photos are hidden.
  final _addedWhileReady = <String>{};

  /// Progress through "Delete all photos"; null when not deleting.
  ({int done, int total})? _deletingAll;

  /// The photos being deleted one by one, by full path.
  final _deletingPhotos = <String>{};
  String? _deleteError;

  bool _deletingSession = false;
  String? _sessionError;

  // Each button keeps focus as it changes: the readiness button from "Make
  // photos available" to "Hide photos", the upload button from primary to
  // outlined. A deleted photo hands focus to the next one.
  final _readyFocus = FocusNode(debugLabel: 'Photos ready');
  final _uploadFocus = FocusNode(debugLabel: 'Upload photos');
  final _deleteAllFocus = FocusNode(debugLabel: 'Delete all photos');
  final _photoFocus = <String, FocusNode>{};

  @override
  void initState() {
    super.initState();
    final id = widget.sessionId;
    _queue = UploadQueue(
      upload: (photo, name) => _admin.uploadSessionPhoto(id, photo, name),
      validate: PhotoRules.sessionPhotoProblem,
      onUploaded: _uploaded,
    )..addListener(_queueChanged);
    _queueSummary = _summarize();
    _subscription = _admin.watchSession(id).listen(_answered, onError: _watchError);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    LeaveWarning.set(this, false);
    // Stops the uploads still running.
    _queue
      ..removeListener(_queueChanged)
      ..dispose();
    _readyFocus.dispose();
    _uploadFocus.dispose();
    _deleteAllFocus.dispose();
    for (final node in _photoFocus.values) {
      node.dispose();
    }
    // The top bar stops naming a session it no longer shows (after signing
    // out, say), once the tree is no longer being taken down.
    final onTitle = widget.onTitle;
    WidgetsBinding.instance.addPostFrameCallback((_) => onTitle(null));
    super.dispose();
  }

  void _answered(SessionLookup lookup) {
    if (lookup is SessionFound) _lastFound = lookup;
    setState(() {
      _lookup = lookup;
      if (lookup is SessionFound && !lookup.booking.photosReady) _addedWhileReady.clear();
    });
    // Deleting it from here: it stays as it was until the page is back on
    // Admin.
    if (_deletingSession && lookup is SessionMissing) return;
    // Deleted elsewhere (another tab): photos still uploading would land in
    // a folder nobody can reach.
    if (lookup is SessionMissing) _queue.cancelAll();
    widget.onTitle(lookup is SessionFound ? sessionDisplayName(lookup.booking) : null);
    if (lookup is SessionFound && _photos == null && !_listing) _listPhotos();
  }

  /// What the page shows: while the session is being deleted from here, as
  /// it was, so it doesn't say "deleted" on its way back to Admin.
  SessionLookup? get _shown => _deletingSession && _lookup is SessionMissing ? _lastFound : _lookup;

  void _watchError(Object error) {
    log('Watching session ${widget.sessionId} failed: $error');
    setState(() => _watchFailed = true);
    widget.onTitle(null);
  }

  Future<void> _listPhotos() async {
    setState(() {
      _listing = true;
      _listFailed = false;
    });
    try {
      final photos = await _admin.listSessionPhotos(widget.sessionId);
      if (mounted) setState(() => _photos = photos);
    } catch (e) {
      log('Listing the photos of ${widget.sessionId} failed: $e');
      if (mounted) setState(() => _listFailed = true);
    } finally {
      if (mounted) setState(() => _listing = false);
    }
  }

  ({bool busy, int items, int failed, int done}) _summarize() => (
        busy: _queue.isBusy,
        items: _queue.items.length,
        failed: _queue.countOf(UploadStatus.failed),
        done: _queue.countOf(UploadStatus.done),
      );

  void _queueChanged() {
    LeaveWarning.set(this, _queue.isBusy);
    final summary = _summarize();
    if (summary != _queueSummary && mounted) setState(() => _queueSummary = summary);
  }

  /// Adds a stored photo to the list, without listing the folder again.
  /// The queue also reports one it found already stored (from another tab,
  /// say), which may be listed by then, so it's added only once.
  void _uploaded(UploadItem item) {
    final photos = _photos;
    if (!mounted || photos == null || photos.any((photo) => photo.name == item.name)) return;
    setState(() {
      _photos = [...photos, _storedPhoto(widget.sessionId, item.name)]..sort((a, b) => a.name.compareTo(b.name));
      if (_lastFound?.booking.photosReady ?? false) _addedWhileReady.add(item.name);
    });
  }

  void _pickPhotos() {
    // First, before anything else: browsers only open the picker while
    // handling the tap. It may never answer (no cancel event in older
    // browsers), so nothing waits on it.
    final picked = AppServices.of(context).pickPhotos(accept: PhotoRules.sessionAccept);
    picked.then(
      (photos) {
        final existing = _photos;
        if (!mounted || photos.isEmpty || existing == null) return;
        // Too late: they're being deleted (or are gone), and what lands now
        // would outlive them.
        if (_deletingSession || _deletingAll != null || _lookup is! SessionFound) return;
        _queue.add(photos, existing: existing.map((photo) => photo.name));
      },
      onError: (Object e) => log('Picking photos failed: $e'),
    );
  }

  Future<void> _confirmLeave(bool didPop, Object? result) async {
    if (didPop) return;
    final stop = await showBrookieConfirm(
      context,
      title: 'Stop uploading?',
      message: 'Photos still uploading will stop. The ones already uploaded stay.',
      confirmLabel: 'Stop uploading',
      cancelLabel: 'Keep uploading',
      destructive: true,
    );
    if (!stop || !mounted) return;
    _queue.cancelAll();
    // Leaving stops whatever Storage hasn't confirmed cancelled yet.
    Navigator.of(context).pop();
  }

  /// Why "Make photos available" can't be pressed yet, or null if it can.
  String? _notReadyReason() {
    if (_deletingSession) return 'The session is being deleted.';
    if (_deletingAll != null) return 'Wait for the photos to finish deleting.';
    if (_queue.isBusy) return 'Wait for the uploads to finish.';
    if (_queue.countOf(UploadStatus.failed) > 0) {
      return 'Some photos didn’t upload. Retry them, or clear the upload list to go ahead without them.';
    }
    final photos = _photos;
    if (photos == null) return _listFailed ? 'Refresh the page to load the photos first.' : 'Checking the photos…';
    if (photos.isEmpty) return 'Upload photos first.';
    return null;
  }

  Future<void> _makeAvailable(Booking booking) async {
    if (_savingReady) return;
    final who = _whoCanDownload(booking);
    final confirmed = await showBrookieConfirm(
      context,
      title: 'Make photos available?',
      message: who == null
          ? '${_photoCount(_photos!.length)}. Nobody can download them until the session says who it’s for.'
          : '${_photoCount(_photos!.length)}. $who can download them.',
      confirmLabel: 'Make photos available',
    );
    if (confirmed && mounted) await _setReady(true);
  }

  Future<void> _setReady(bool ready) async {
    if (_savingReady) return;
    setState(() {
      _savingReadyTo = ready;
      _readyError = null;
    });
    try {
      await _admin.setPhotosReady(widget.sessionId, ready);
    } catch (e) {
      if (mounted) setState(() => _readyError = _messageFor(e, 'That didn’t save. Try again.'));
    } finally {
      if (mounted) setState(() => _savingReadyTo = null);
    }
  }

  /// Whether the page shows [booking]'s photos as available. While a change
  /// saves it shows them as they were: the session's local copy changes at
  /// once (Firestore's latency compensation), but families only see the
  /// change once the server has it, and the pressed button stays busy
  /// until then.
  bool _shownReady(Booking booking) => switch (_savingReadyTo) {
        final saving? => !saving,
        null => booking.photosReady,
      };

  FocusNode _focusFor(StoredPhoto photo) =>
      _photoFocus.putIfAbsent(photo.fullPath, () => FocusNode(debugLabel: 'Delete ${photo.name}'));

  /// Whether [node] has focus, or gets it back when the confirmation over
  /// the page closes.
  bool _focusIsOn(FocusNode node) => node.hasFocus || FocusScope.of(context).focusedChild == node;

  /// Takes [gone] off the list. If one of their buttons had focus, it moves
  /// to the photo now in its place (or the one before, or "Upload photos"),
  /// rather than back to the top of the page.
  void _removePhotos(Set<String> gone) {
    final photos = _photos!;
    final focused = photos.indexWhere((photo) {
      final node = _photoFocus[photo.fullPath];
      return node != null && gone.contains(photo.fullPath) && _focusIsOn(node);
    });
    final rest = [
      for (final photo in photos)
        if (!gone.contains(photo.fullPath)) photo,
    ];
    if (focused >= 0) {
      final kept = photos.take(focused).where((photo) => !gone.contains(photo.fullPath)).length;
      (rest.isEmpty ? _uploadFocus : _focusFor(rest[math.min(kept, rest.length - 1)])).requestFocus();
    }
    setState(() {
      _photos = rest;
      _addedWhileReady.removeAll([
        for (final photo in photos)
          if (gone.contains(photo.fullPath)) photo.name,
      ]);
    });
    // Their buttons go with the next frame.
    final nodes = [
      for (final path in gone)
        if (_photoFocus.remove(path) case final node?) node,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in nodes) {
        node.dispose();
      }
    });
  }

  Future<void> _deletePhoto(StoredPhoto photo) async {
    if (_deletingPhotos.contains(photo.fullPath)) return;
    final confirmed = await showBrookieConfirm(
      context,
      title: 'Delete this photo?',
      message: '${photo.name} will be deleted for good.',
      confirmLabel: 'Delete photo',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _deletingPhotos.add(photo.fullPath);
      _deleteError = null;
    });
    try {
      await _admin.deletePhoto(photo);
      if (mounted) _removePhotos({photo.fullPath});
    } catch (e) {
      if (mounted) setState(() => _deleteError = _messageFor(e, '${photo.name} wasn’t deleted. Try again.'));
    } finally {
      if (mounted) setState(() => _deletingPhotos.remove(photo.fullPath));
    }
  }

  Future<void> _deleteAll() async {
    final photos = List.of(_photos ?? const <StoredPhoto>[]);
    if (photos.isEmpty || _deletingAll != null) return;
    // Like deleting the session: nobody downloads a half-deleted gallery,
    // or is left with a download of nothing.
    final hideFirst = _lastFound?.booking.photosReady ?? false;
    final confirmed = await showBrookieConfirm(
      context,
      title: 'Delete all photos?',
      message: [
        'All ${_photoCount(photos.length)} in this session will be deleted for good.',
        if (hideFirst) 'They’ll be hidden from the family first.',
      ].join(' '),
      confirmLabel: 'Delete all photos',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _deletingAll = (done: 0, total: photos.length);
      _deleteError = null;
    });
    if (hideFirst) {
      try {
        await _admin.setPhotosReady(widget.sessionId, false);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _deletingAll = null;
          _deleteError = 'The photos weren’t hidden, so none were deleted. ${_messageFor(e, 'Try again.')}';
        });
        return;
      }
      if (!mounted) return;
    }
    // A few at a time, like the uploads; the first failure stops the rest.
    var next = 0;
    Object? failure;
    Future<void> deleteSome() async {
      while (mounted && failure == null && next < photos.length) {
        final photo = photos[next++];
        try {
          await _admin.deletePhoto(photo);
        } catch (e) {
          failure ??= e;
          return;
        }
        if (!mounted) return;
        _removePhotos({photo.fullPath});
        setState(() => _deletingAll = (done: _deletingAll!.done + 1, total: photos.length));
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) deleteSome()]);
    if (!mounted) return;
    final done = _deletingAll!.done;
    final error = failure;
    // The button goes with the last photo; focus goes to "Upload photos",
    // once it's built enabled again.
    final refocus = _photos!.isEmpty && _focusIsOn(_deleteAllFocus);
    setState(() {
      _deletingAll = null;
      if (error != null) {
        final why = _messageFor(error, 'The rest weren’t deleted. Try again.');
        _deleteError = 'Deleted $done of ${photos.length}. $why';
      }
    });
    if (refocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _uploadFocus.requestFocus();
      });
    }
  }

  /// Completes once no uploads are waiting or running.
  Future<void> _uploadsStopped() {
    if (!_queue.isBusy) return Future.value();
    final stopped = Completer<void>();
    void check() {
      if (_queue.isBusy || stopped.isCompleted) return;
      _queue.removeListener(check);
      stopped.complete();
    }

    _queue.addListener(check);
    return stopped.future;
  }

  Future<void> _deleteSession(Booking booking) async {
    if (_deletingSession) return;
    final photos = _photos;
    final name = sessionDisplayName(booking);
    final confirmed = await showBrookieConfirm(
      context,
      title: 'Delete this session?',
      message: [
        photos == null || photos.isEmpty
            ? 'The session will be deleted for good.'
            : 'The session and its ${_photoCount(photos.length)} will be deleted for good.',
        if (_queue.isBusy) 'Uploads still running will stop.',
      ].join(' '),
      confirmLabel: 'Delete session',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _deletingSession = true;
      _sessionError = null;
    });
    try {
      // Nothing may land in its folder after the photos are deleted.
      _queue.cancelAll();
      await _uploadsStopped();
      await _admin.deleteSession(widget.sessionId);
      if (!mounted) return;
      // Still deleting as far as the page shows, while it fades out.
      AdminPage.returnWithNotice(context, 'Deleted ${_inSentence(name)}’s session.');
      // With nothing below it to go back to, it stays, and says it's gone.
      if (ModalRoute.isCurrentOf(context) ?? false) {
        setState(() => _deletingSession = false);
        widget.onTitle(null);
      }
    } catch (e) {
      if (!mounted) return;
      final why = _messageFor(e, 'The session wasn’t deleted. Try again.');
      final hadPhotos = photos != null && photos.isNotEmpty;
      setState(() {
        _deletingSession = false;
        _sessionError =
            hadPhotos ? '$why Some of its photos may already be deleted: the list shows what’s left.' : why;
      });
      // It may have gone part way: the document is deleted last, after the
      // photos, so the list is checked again.
      if (_lookup is SessionMissing) {
        widget.onTitle(null);
      } else if (!_listing) {
        setState(() => _photos = null);
        _listPhotos();
      }
    }
  }

  void _edit(Booking booking) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => SessionFormPage(session: booking)));
  }

  @override
  Widget build(BuildContext context) {
    final lookup = _shown;
    final Widget content;
    if (_watchFailed) {
      content = const InlineMessage(message: 'We couldn’t load this session. Refresh the page to try again.');
    } else if (lookup == null) {
      content = const _Spinner();
    } else {
      content = switch (lookup) {
        SessionFound(:final booking) => _session(context, booking),
        SessionMissing() => const _Missing(),
        SessionUnreadable(:final booking) => _Unreadable(booking: booking),
      };
    }
    return PopScope<Object?>(
      canPop: !_queue.isBusy,
      onPopInvokedWithResult: _confirmLeave,
      child: AdminFrame(child: content),
    );
  }

  Widget _session(BuildContext context, Booking booking) {
    final gap = SizedBox(height: BrookieLayout.sectionGap(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Details(booking: booking, onEdit: booking.isAdHoc ? () => _edit(booking) : null),
        gap,
        _WhoCanDownload(booking: booking),
        gap,
        _readiness(context, booking),
        gap,
        _photosSection(context, booking),
        if (booking.isAdHoc) ...[
          gap,
          _deleteSessionSection(context, booking),
        ],
      ],
    );
  }

  /// Whether the family can download the photos, and the button that
  /// changes it.
  Widget _readiness(BuildContext context, Booking booking) {
    final c = BrookieColors.of(context);
    final ready = _shownReady(booking);
    final reason = ready ? null : _notReadyReason();
    // Failed uploads are the only thing holding it back, and the admin may
    // choose to go ahead without them.
    final failuresInTheWay = reason != null &&
        !_deletingSession &&
        _deletingAll == null &&
        !_queue.isBusy &&
        _queue.countOf(UploadStatus.failed) > 0;
    final error = _readyError;
    final undeliverable = switch (booking.status) {
      BookingStatus.pending => 'Payment is still pending, so the family can’t download photos yet, even once '
          'they’re available.',
      BookingStatus.cancelled => 'This booking was cancelled, so the family can’t download its photos.',
      BookingStatus.refunded => 'This booking was refunded, so the family can’t download its photos.',
      BookingStatus.paid || BookingStatus.adhoc => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeading('Downloads'),
        const SizedBox(height: BrookieSpace.s3),
        PhotosReadyTag(ready: ready, status: booking.status),
        const SizedBox(height: BrookieSpace.s2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
          child: Text(switch ((ready, _photos?.isEmpty ?? false)) {
            // Their download would fail: there's nothing in it.
            (true, true) => 'There are no photos to download. Upload them, or hide the photos until you do.',
            (true, false) => 'The family can download every photo below as one zip.',
            (false, _) => 'The family can’t download the photos until you make them available.',
          }),
        ),
        const SizedBox(height: BrookieSpace.s4),
        if (ready)
          // Never disabled: hiding them is always possible.
          BusyButton(
            label: 'Hide photos',
            busyLabel: 'Hiding photos…',
            busy: _savingReady,
            focusNode: _readyFocus,
            onPressed: () => _setReady(false),
          )
        else
          BusyButton(
            label: 'Make photos available',
            busyLabel: 'Making photos available…',
            busy: _savingReady,
            // The page's primary action once there's nothing left to upload.
            kind: reason == null ? BusyButtonKind.filled : BusyButtonKind.outlined,
            focusNode: _readyFocus,
            onPressed: reason == null ? () => _makeAvailable(booking) : null,
          ),
        if (reason != null) ...[
          const SizedBox(height: BrookieSpace.s2),
          Text(reason, style: BrookieType.small.copyWith(color: c.inkSoft)),
          if (failuresInTheWay) TextButton(onPressed: _queue.clearFinished, child: const Text('Clear upload list')),
        ],
        if (ready && _addedWhileReady.isNotEmpty) ...[
          const SizedBox(height: BrookieSpace.s4),
          const InlineMessage(
            message: 'Families who already downloaded need to download again to get these.',
            tone: StatusTone.neutral,
          ),
        ],
        if (undeliverable != null) ...[
          const SizedBox(height: BrookieSpace.s4),
          InlineMessage(message: undeliverable, tone: StatusTone.neutral),
        ],
        if (error != null) ...[
          const SizedBox(height: BrookieSpace.s4),
          InlineMessage(message: error),
        ],
      ],
    );
  }

  /// Uploading, then the photos already here.
  Widget _photosSection(BuildContext context, Booking booking) {
    final photos = _photos;
    final deletingAll = _deletingAll;
    final error = _deleteError;
    // Primary until the photos can be made available; then that is.
    final primary = !_shownReady(booking) && _notReadyReason() != null;
    final canUpload = photos != null && deletingAll == null && !_deletingSession;
    final upload = primary
        ? FilledButton.icon(
            onPressed: canUpload ? _pickPhotos : null,
            focusNode: _uploadFocus,
            icon: const Icon(Icons.upload_outlined),
            label: const Text('Upload photos'),
          )
        : OutlinedButton.icon(
            onPressed: canUpload ? _pickPhotos : null,
            focusNode: _uploadFocus,
            icon: const Icon(Icons.upload_outlined),
            label: const Text('Upload photos'),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminHeading('Photos'),
        const SizedBox(height: BrookieSpace.s3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
          child: Text(
            'Upload the edited photos, each under ${PhotoRules.sessionMaxBytes ~/ (1024 * 1024)} MB. Ones '
            'already here are skipped, so after a problem you can pick the whole folder again.',
          ),
        ),
        const SizedBox(height: BrookieSpace.s4),
        Align(alignment: AlignmentDirectional.centerStart, child: upload),
        // Not while the session is being deleted: "Retry failed" would put
        // photos in its folder after it's emptied.
        if (_queue.items.isNotEmpty && !_deletingSession) ...[
          const SizedBox(height: BrookieSpace.s5),
          UploadProgressList(queue: _queue),
        ],
        const SizedBox(height: BrookieSpace.s6),
        if (photos == null)
          _listFailed
              ? const InlineMessage(
                  message: 'We couldn’t list this session’s photos. Refresh the page to try again.',
                )
              : const _Spinner()
        else if (photos.isEmpty)
          const EmptyState(message: 'No photos yet. Upload them above.')
        else ...[
          // The count, with "Delete all photos" at its right (or under it
          // when both don't fit). Full width so spaceBetween can push it.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: BrookieSpace.s3,
              children: [
                Text(_photoCount(photos.length), style: Theme.of(context).textTheme.titleMedium),
                BusyButton(
                  label: 'Delete all photos',
                  busyLabel: 'Deleting ${deletingAll?.done ?? 0} of ${deletingAll?.total ?? 0}…',
                  busy: deletingAll != null,
                  kind: BusyButtonKind.text,
                  icon: Icons.delete_outline,
                  focusNode: _deleteAllFocus,
                  onPressed: _deletingSession ? null : _deleteAll,
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: BrookieSpace.s3),
            InlineMessage(message: error),
          ],
          const SizedBox(height: BrookieSpace.s3),
          for (final photo in photos)
            _PhotoRow(
              key: ValueKey(photo.fullPath),
              photo: photo,
              focusNode: _focusFor(photo),
              deleting: _deletingPhotos.contains(photo.fullPath),
              // Not while they're all going.
              onDelete: deletingAll == null && !_deletingSession ? () => _deletePhoto(photo) : null,
            ),
        ],
      ],
    );
  }

  Widget _deleteSessionSection(BuildContext context, Booking booking) {
    final error = _sessionError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeading('Delete this session'),
        const SizedBox(height: BrookieSpace.s2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
          child: const Text(
            'Deletes the session and its photos for good. The family won’t be able to download them.',
          ),
        ),
        const SizedBox(height: BrookieSpace.s4),
        BusyButton(
          label: 'Delete session',
          busyLabel: 'Deleting session…',
          busy: _deletingSession,
          icon: Icons.delete_outline,
          onPressed: _deletingAll == null ? () => _deleteSession(booking) : null,
        ),
        if (error != null) ...[
          const SizedBox(height: BrookieSpace.s4),
          InlineMessage(message: error),
        ],
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

/// Who it's for, the package, when and where, and how it was paid for.
class _Details extends StatelessWidget {
  const _Details({required this.booking, required this.onEdit});

  final Booking booking;

  /// Opens the form; null for bookings, whose details the app can't change.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final time = booking.time;
    final location = booking.location;
    final onEdit = this.onEdit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminHeading(sessionDisplayName(booking), page: true),
        const SizedBox(height: BrookieSpace.s3),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: BrookieSpace.s3,
          runSpacing: BrookieSpace.s2,
          children: [
            Text(booking.title, style: TextStyle(color: c.inkSoft)),
            BookingStatusTag(status: booking.status),
          ],
        ),
        const SizedBox(height: BrookieSpace.s4),
        DetailLine(icon: Icons.event_outlined, text: formatDayShort(booking.date, now: DateTime.now())),
        if (time != null) ...[
          const SizedBox(height: BrookieSpace.s2),
          DetailLine(icon: Icons.schedule_outlined, text: SessionTime.clockLabel(time.hour, time.minute)),
        ],
        if (location != null) ...[
          const SizedBox(height: BrookieSpace.s2),
          DetailLine(icon: Icons.place_outlined, text: location),
        ],
        if (onEdit != null) ...[
          const SizedBox(height: BrookieSpace.s5),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit details'),
          ),
        ],
      ],
    );
  }
}

/// Which Google account can download the photos, and a message telling the
/// family where and how.
class _WhoCanDownload extends StatelessWidget {
  const _WhoCanDownload({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final email = booking.email;
    final nobody = booking.isAdHoc
        ? 'Nobody yet: the session has no email. Add one with “Edit details”.'
        : 'Nobody yet: no Google account is linked to this booking. Add the family’s user ID (uid) in the '
            'Firestore console.';
    // Selectable, to copy a uid or an email.
    final lines = <Widget>[
      SelectableText(_whoCanDownload(booking) ?? nobody),
      if (!booking.isAdHoc && email != null) SelectableText('Email on the booking: $email'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminHeading('Who can download'),
        const SizedBox(height: BrookieSpace.s3),
        for (final (i, line) in lines.indexed) ...[
          if (i > 0) const SizedBox(height: BrookieSpace.s1),
          line,
        ],
        const SizedBox(height: BrookieSpace.s5),
        _ShareMessage(booking: booking),
      ],
    );
  }
}

/// "Share with the family": the message to send, with the link to "Your
/// sessions" and the account to sign in with, and "Copy message".
class _ShareMessage extends StatefulWidget {
  const _ShareMessage({required this.booking});

  final Booking booking;

  @override
  State<_ShareMessage> createState() => _ShareMessageState();
}

class _ShareMessageState extends State<_ShareMessage> {
  /// The message last copied, so the button says "Message copied" until
  /// the message changes (a new email, say).
  String? _copied;

  Future<void> _copy(String message) async {
    try {
      await Clipboard.setData(ClipboardData(text: message));
    } on PlatformException {
      return; // The browser refused; the message can still be selected and copied.
    }
    if (mounted) setState(() => _copied = message);
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final message = AdminSessionPage.shareMessage(widget.booking);
    final copied = _copied == message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('Share with the family', style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: BrookieSpace.s2),
        if (!widget.booking.photosReady) ...[
          Text('Send it once the photos are available.', style: TextStyle(color: c.inkSoft)),
          const SizedBox(height: BrookieSpace.s3),
        ],
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(color: c.surfaceSunk, borderRadius: BorderRadius.circular(BrookieRadius.sm)),
            child: Padding(
              padding: const EdgeInsets.all(BrookieSpace.s4),
              child: SelectableText(message, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
        ),
        const SizedBox(height: BrookieSpace.s3),
        // One node and a live region, so screen readers hear "Message copied".
        MergeSemantics(
          child: Semantics(
            liveRegion: true,
            child: OutlinedButton.icon(
              onPressed: () => _copy(message),
              icon: Icon(copied ? Icons.check : Icons.content_copy_outlined),
              label: Text(copied ? 'Message copied' : 'Copy message'),
            ),
          ),
        ),
      ],
    );
  }
}

/// One photo in the list: its name (with its subfolder) and a delete button.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    super.key,
    required this.photo,
    required this.focusNode,
    required this.deleting,
    required this.onDelete,
  });

  final StoredPhoto photo;
  final FocusNode focusNode;
  final bool deleting;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final onDelete = this.onDelete;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BrookieSpace.s1),
        child: Row(
          children: [
            Expanded(child: Text(photo.name)),
            const SizedBox(width: BrookieSpace.s3),
            // Stays enabled while it works, so focus stays put.
            IconButton(
              focusNode: focusNode,
              tooltip: 'Delete ${photo.name}',
              onPressed: onDelete == null ? null : (deleting ? () {} : onDelete),
              icon: deleting
                  ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.inkSoft))
                  : const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// The session is gone: deleted, here or elsewhere, or never there.
class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      message: 'This session was deleted.',
      action: OutlinedButton(
        onPressed: () => AdminPage.open(context),
        child: const Text('Go to Admin'),
      ),
    );
  }
}

/// The session's document is there but can't be read (a typo in a booking
/// entered by hand).
class _Unreadable extends StatelessWidget {
  const _Unreadable({required this.booking});

  final UnreadableBooking booking;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineMessage(
          message: 'This session couldn’t be read: ${booking.problem}. Fix it in the Firestore console.',
        ),
        const SizedBox(height: BrookieSpace.s3),
        // Selectable, to paste into the console's search.
        SelectableText('Document ID: ${booking.id}', style: TextStyle(color: c.inkSoft)),
        const SizedBox(height: BrookieSpace.s5),
        OutlinedButton(
          onPressed: () => AdminPage.open(context),
          child: const Text('Go to Admin'),
        ),
      ],
    );
  }
}
