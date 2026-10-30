import 'dart:async';

import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/picked_photo.dart';
import 'package:brookie_babies/models/session_details.dart';
import 'package:brookie_babies/models/session_lookup.dart';
import 'package:brookie_babies/models/stored_photo.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/services/portfolio_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const testUser = AppUser(uid: 'uid123', email: 'parent@example.com', displayName: 'Pat Parent');

/// In-memory [AuthService] for widget tests.
class FakeAuthService implements AuthService {
  FakeAuthService({AppUser? signedInAs, this.admin = false}) : _user = signedInAs;

  final _changes = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  /// What the next [signInWithGoogle] returns: a user, or null as if the
  /// Google popup was closed.
  AppUser? nextSignIn;

  /// If set, the next [signInWithGoogle] throws it instead.
  SignInException? nextSignInError;

  int signInCalls = 0;

  /// What [isAdmin] says for a signed-in user.
  bool admin;

  /// If set, [isAdmin] fails with it (while signed in).
  Object? isAdminError;

  /// The `refresh` flag of every [isAdmin] call, in order.
  final isAdminCalls = <bool>[];

  /// While true, [isAdmin] calls wait for [answerIsAdmin], so a test can see
  /// the page waiting.
  bool holdIsAdmin = false;

  // Created per call, so it belongs to the test's fake-async zone.
  final _heldIsAdmin = <Completer<bool>>[];

  @override
  Stream<AppUser?> get authStateChanges => _changes.stream;

  @override
  AppUser? get currentUser => _user;

  @override
  Future<AppUser?> signInWithGoogle() async {
    signInCalls++;
    final error = nextSignInError;
    if (error != null) throw error;
    final user = nextSignIn;
    if (user != null) _setUser(user);
    return user;
  }

  @override
  Future<void> signOut() async => _setUser(null);

  @override
  Future<bool> isAdmin({bool refresh = false}) {
    isAdminCalls.add(refresh);
    if (_user == null) return Future.value(false);
    if (holdIsAdmin) {
      final held = Completer<bool>();
      _heldIsAdmin.add(held);
      return held.future;
    }
    final error = isAdminError;
    return error == null ? Future.value(admin) : Future.error(error);
  }

  /// Answers the oldest held [isAdmin] call with [admin] (or fails it with
  /// [isAdminError]).
  void answerIsAdmin() {
    final held = _heldIsAdmin.removeAt(0);
    final error = isAdminError;
    error == null ? held.complete(admin) : held.completeError(error);
  }

  void _setUser(AppUser? user) {
    _user = user;
    _changes.add(user);
  }
}

/// [BookingService] that returns fixed bookings (or [error]) for any user.
class FakeBookingService implements BookingService {
  FakeBookingService([this.bookings = const [], this.unreadable = 0]);

  final List<Booking> bookings;
  final int unreadable;
  Object? error;

  /// The uid of each user watched, in order.
  final watchedUids = <String>[];

  /// Each user watched, in order (for their email).
  final watchedUsers = <AppUser>[];

  @override
  Stream<UserBookings> watchBookings(AppUser user) {
    watchedUids.add(user.uid);
    watchedUsers.add(user);
    final error = this.error;
    return error == null
        ? Stream.value((bookings: bookings, unreadable: unreadable))
        : Stream.error(error);
  }
}

/// [GalleryService] whose downloads stay pending until the test calls
/// [complete] or [fail]; [progress] reports how the zip's build is going.
class FakeGalleryService implements GalleryService {
  final requested = <String>[];

  // Created per call rather than up front, so it belongs to the test's
  // fake-async zone and completing it reaches the widget.
  Completer<GalleryDownload>? _pending;
  GalleryProgressCallback? _onProgress;

  @override
  Future<GalleryDownload> prepareDownload(String bookingId, {GalleryProgressCallback? onProgress}) {
    requested.add(bookingId);
    _onProgress = onProgress;
    return (_pending = Completer()).future;
  }

  /// Hands [p] to the latest download's onProgress, as a chunk from the
  /// function would be.
  void progress(GalleryProgress p) => _onProgress!(p);

  void complete(GalleryDownload download) => _pending!.complete(download);

  void fail(Object error) => _pending!.completeError(error);
}

/// [PortfolioService] that returns fixed [photos] (the first `limit` of
/// them), or throws [error].
class FakePortfolioService implements PortfolioService {
  FakePortfolioService([this.photos = const []]);

  final List<Uri> photos;
  Object? error;

  /// The `limit` of the last [photoUrls] call.
  int? requestedLimit;

  @override
  Future<List<Uri>> photoUrls({int? limit}) async {
    requestedLimit = limit;
    final error = this.error;
    if (error != null) throw error;
    return limit == null ? photos : photos.take(limit).toList();
  }
}

/// Records the URLs the app opens instead of launching them.
class FakeUrlOpener {
  final opened = <({Uri url, String? windowName})>[];

  /// Called with each URL before it's recorded: how things stand as the
  /// browser is handed it.
  void Function(Uri url)? onOpen;

  Future<bool> call(Uri url, {String? webOnlyWindowName}) async {
    onOpen?.call(url);
    opened.add((url: url, windowName: webOnlyWindowName));
    return true;
  }
}

/// A [PickPhotos] that hands back [next] instead of opening a file picker.
class FakePhotoPicker {
  /// What the next pick returns; empty is a cancelled picker.
  List<PickedPhoto> next = const [];

  /// While true, picks never answer, like a browser that doesn't report a
  /// cancelled picker.
  bool neverAnswers = false;

  /// The `accept` of every pick, in order.
  final accepts = <String>[];

  Future<List<PickedPhoto>> call({required String accept}) {
    accepts.add(accept);
    return neverAnswers ? Completer<List<PickedPhoto>>().future : Future.value(next);
  }
}

/// A picked file named [name] (its contents are empty bytes; [size] is what
/// the rules see).
PickedPhoto testPhoto(String name, {int size = 2 * 1024 * 1024, String contentType = 'image/jpeg'}) =>
    PickedPhoto(name: name, size: size, contentType: contentType, data: Uint8List(0));

/// A session for admin tests: ad hoc unless [status] says otherwise (then
/// with a package unless one is given).
Booking testSession(
  String id, {
  String? name = 'The Harper family',
  String? email = 'harper@example.com',
  DateTime? date,
  ({int hour, int minute})? time,
  String? location,
  BookingStatus status = BookingStatus.adhoc,
  String? packageName,
  bool photosReady = false,
  String? uid,
}) {
  return Booking(
    id: id,
    packageName: packageName ?? (status == BookingStatus.adhoc ? null : 'Premium'),
    date: date ?? DateTime(2999, 3, 4),
    time: time,
    location: location,
    status: status,
    photosReady: photosReady,
    uid: uid ?? (status == BookingStatus.adhoc ? null : 'uid-$id'),
    email: email,
    name: name,
  );
}

/// An [AdminException] of [kind], with the app's message for the kinds that
/// have one.
AdminException adminError(AdminErrorKind kind, [String? message]) => AdminException(
      message ??
          switch (kind) {
            AdminErrorKind.denied => kAdminDeniedMessage,
            AdminErrorKind.offline => kAdminOfflineMessage,
            AdminErrorKind.quota => kAdminQuotaMessage,
            _ => 'Fake ${kind.name} error.',
          },
      kind,
    );

/// One upload by [FakeAdminService]: it runs until the test calls
/// [setProgress], [complete] or [fail], or the app calls [cancel].
class FakePhotoUpload implements PhotoUpload {
  FakePhotoUpload({required this.fullPath, required this.photo, required this.name, this.onStored}) {
    // Nobody may be waiting on a failure (a test that drops the upload), and
    // that mustn't count as an uncaught error.
    _done.future.ignore();
  }

  /// Where it's going: 'galleries/s1/IMG_1.jpg' or '_admin/gallery/IMG_1.jpg'.
  final String fullPath;
  final PickedPhoto photo;
  final String name;

  /// Called when it completes, before [done] does.
  final VoidCallback? onStored;

  final _progress = ValueNotifier<double>(0);
  final _done = Completer<void>();

  /// Whether the app called [cancel].
  bool cancelled = false;

  bool get isFinished => _done.isCompleted;

  @override
  ValueListenable<double> get progress => _progress;

  @override
  Future<void> get done => _done.future;

  void setProgress(double value) => _progress.value = value;

  /// Stores the photo.
  void complete() {
    if (isFinished) return;
    _progress.value = 1;
    onStored?.call();
    _done.complete();
  }

  /// Fails with [adminError] of [kind].
  void fail([AdminErrorKind kind = AdminErrorKind.unknown, String? message]) => failWith(adminError(kind, message));

  void failWith(Object error) {
    if (!isFinished) _done.completeError(error);
  }

  @override
  void cancel() {
    cancelled = true;
    fail(AdminErrorKind.cancelled, 'Upload cancelled.');
  }
}

/// In-memory [AdminService] for widget tests: sessions with live streams
/// that emit again on every change, photos per session, the home page
/// library and its chosen names, and uploads the test finishes.
///
/// Failures: [nextError] fails the next call; [errors] fails every call to
/// a method by name ('listSessionPhotos'), uploads included; [watchError]
/// fails the live streams as they're listened to, [failLiveStreams] while
/// they run. Writes take [writeDelay]. Every call is logged in [calls].
class FakeAdminService implements AdminService {
  FakeAdminService({
    Iterable<Booking> sessions = const [],
    Iterable<UnreadableBooking> unreadable = const [],
    Map<String, List<String>> sessionPhotos = const {},
    Iterable<String> library = const [],
    this.homeNames,
    this.autoCompleteUploads = false,
  }) {
    for (final session in sessions) {
      this.sessions[session.id] = session;
    }
    this.unreadable.addAll(unreadable);
    sessionPhotos.forEach((id, names) => this.sessionPhotos[id] = [...names]);
    this.library.addAll(library);
  }

  /// Sessions by id, in the order added. After changing it (or [unreadable])
  /// directly, call [notifyChanged].
  final sessions = <String, Booking>{};
  final unreadable = <UnreadableBooking>[];

  /// Photo names (relative, 'edits/IMG_1.jpg' for a subfolder) by session id.
  final sessionPhotos = <String, List<String>>{};

  /// File names in `_admin/gallery`.
  final library = <String>[];

  /// Photos in [library] listed without a link, as when fetching one fails.
  final unlinked = <String>{};

  /// `site/home.photos`; null if never saved.
  List<String>? homeNames;

  /// Each call as 'method(arguments)', such as 'setPhotosReady(s1, true)'.
  final calls = <String>[];

  /// Thrown by the next call to any method but the uploads, then cleared.
  Object? nextError;

  /// Thrown by every call to the method named, until removed. For an
  /// upload, its [PhotoUpload.done] fails with it at once.
  final errors = <String, Object>{};

  /// If set, the live streams fail with it when listened to.
  Object? watchError;

  /// How long each write (create, update, setPhotosReady, deleteSession,
  /// deletePhoto, saveHomePhotos) takes.
  Duration writeDelay = Duration.zero;

  /// Whether uploads finish as soon as they start.
  bool autoCompleteUploads;

  /// Every upload started, in order.
  final uploads = <FakePhotoUpload>[];

  /// The id each [createSession] call was for, in order.
  final createSessionIds = <String>[];

  var _nextId = 1;
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Has the live streams emit the current state again.
  void notifyChanged() => _changes.add(null);

  /// Fails the live streams that are running, which then end, as
  /// Firestore's do.
  void failLiveStreams(Object error) => _changes.addError(error);

  /// The uploads that haven't finished.
  List<FakePhotoUpload> get pendingUploads => [
        for (final upload in uploads)
          if (!upload.isFinished) upload,
      ];

  void _fail(String method) {
    final once = nextError;
    if (once != null) {
      nextError = null;
      throw once;
    }
    final always = errors[method];
    if (always != null) throw always;
  }

  Future<void> _write(String method, String call) async {
    calls.add(call);
    if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
    _fail(method);
  }

  Stream<T> _live<T>(T Function() current) => Stream.multi((controller) {
        final error = watchError;
        if (error != null) {
          controller.addError(error);
          controller.close();
          return;
        }
        controller.add(current());
        late final StreamSubscription<void> changes;
        changes = _changes.stream.listen(
          (_) => controller.add(current()),
          // Firestore ends a listener after its first error.
          onError: (Object error) {
            changes.cancel();
            controller
              ..addError(error)
              ..close();
          },
        );
        controller.onCancel = changes.cancel;
      });

  SessionLookup _lookup(String id) {
    final session = sessions[id];
    if (session != null) return SessionFound(session);
    for (final bad in unreadable) {
      if (bad.id == id) return SessionUnreadable(bad);
    }
    return const SessionMissing();
  }

  /// Session [id], for a change to it. One that isn't there is refused, as
  /// the rules refuse it (they read the document's status), so the app says
  /// what it says for any refusal.
  Booking _session(String id) {
    final session = sessions[id];
    if (session == null) throw adminError(AdminErrorKind.denied);
    return session;
  }

  static Booking _adHoc(String id, SessionDetails details, {required bool photosReady}) => Booking(
        id: id,
        packageName: details.packageName,
        date: DateTime(details.date.year, details.date.month, details.date.day),
        time: details.time,
        location: details.location,
        status: BookingStatus.adhoc,
        photosReady: photosReady,
        email: SessionRules.normalizeEmail(details.email),
        name: details.name.trim(),
      );

  @override
  Stream<AllSessions> watchSessions() {
    calls.add('watchSessions()');
    return _live(() => (sessions: sessions.values.toList(), unreadable: List.of(unreadable)));
  }

  @override
  Stream<SessionLookup> watchSession(String id) {
    calls.add('watchSession($id)');
    return _live(() => _lookup(id));
  }

  @override
  String newSessionId() => 'session-${_nextId++}';

  @override
  Future<String> createSession(SessionDetails details, {String? id}) async {
    final sessionId = id ?? newSessionId();
    createSessionIds.add(sessionId);
    await _write('createSession', 'createSession(${details.name.trim()})');
    // Already saved by an earlier try: the real one finds it, never makes a
    // second session, and changes it to these details, the ones sent last.
    // Anything else there is refused, as the rules refuse it.
    final saved = sessions[sessionId];
    if (saved != null && (id == null || !saved.isAdHoc)) throw adminError(AdminErrorKind.denied);
    sessions[sessionId] = _adHoc(sessionId, details, photosReady: saved?.photosReady ?? false);
    notifyChanged();
    return sessionId;
  }

  @override
  Future<void> updateSession(Booking session, SessionDetails details) async {
    // The app only offers this for ad hoc sessions; anything else is a bug.
    if (!session.isAdHoc) throw StateError('updateSession(${session.id}) is for ad hoc sessions only');
    await _write('updateSession', 'updateSession(${session.id})');
    final current = _session(session.id);
    sessions[session.id] = _adHoc(session.id, details, photosReady: current.photosReady);
    notifyChanged();
  }

  @override
  Future<void> setPhotosReady(String id, bool ready) async {
    await _write('setPhotosReady', 'setPhotosReady($id, $ready)');
    final s = _session(id);
    sessions[id] = Booking(
      id: s.id,
      packageName: s.packageName,
      date: s.date,
      time: s.time,
      location: s.location,
      status: s.status,
      photosReady: ready,
      uid: s.uid,
      email: s.email,
      name: s.name,
    );
    notifyChanged();
  }

  @override
  Future<void> deleteSession(String id) async {
    if (sessions[id]?.isAdHoc == false) throw StateError('deleteSession($id) is for ad hoc sessions only');
    await _write('deleteSession', 'deleteSession($id)');
    // Already gone counts as deleted, as it does for the real one.
    sessions.remove(id);
    sessionPhotos.remove(id);
    notifyChanged();
  }

  @override
  Future<List<StoredPhoto>> listSessionPhotos(String id) async {
    calls.add('listSessionPhotos($id)');
    _fail('listSessionPhotos');
    final names = [...?sessionPhotos[id]]..sort();
    return [for (final name in names) StoredPhoto(name: name, fullPath: 'galleries/$id/$name')];
  }

  @override
  PhotoUpload uploadSessionPhoto(String sessionId, PickedPhoto photo, String name) =>
      _upload('uploadSessionPhoto', 'galleries/$sessionId/$name', photo, name,
          sessionPhotos.putIfAbsent(sessionId, () => []));

  /// One that leaves the zip is logged with ', deleteZip: false' after its
  /// path.
  @override
  Future<void> deletePhoto(StoredPhoto photo, {bool deleteZip = true}) async {
    await _write('deletePhoto', 'deletePhoto(${photo.fullPath}${deleteZip ? '' : ', deleteZip: false'})');
    if (photo.fullPath.startsWith('${StoragePortfolioService.folder}/')) {
      library.remove(photo.name);
    } else {
      // 'galleries/<id>/<name>'
      final id = photo.fullPath.split('/')[1];
      sessionPhotos[id]?.remove(photo.name);
    }
  }

  @override
  Future<List<StoredPhoto>> listHomeLibrary() async {
    calls.add('listHomeLibrary()');
    _fail('listHomeLibrary');
    return [
      for (final name in [...library]..sort())
        StoredPhoto(
          name: name,
          fullPath: '${StoragePortfolioService.folder}/$name',
          url: StoragePortfolioService.isPhoto(name) && !unlinked.contains(name)
              ? Uri.parse('https://storage.example.com/$name')
              : null,
        ),
    ];
  }

  @override
  PhotoUpload uploadToHomeLibrary(PickedPhoto photo, String name) =>
      _upload('uploadToHomeLibrary', '${StoragePortfolioService.folder}/$name', photo, name, library);

  FakePhotoUpload _upload(String method, String fullPath, PickedPhoto photo, String name, List<String> into) {
    calls.add('$method($fullPath)');
    final upload = FakePhotoUpload(fullPath: fullPath, photo: photo, name: name, onStored: () => into.add(name));
    uploads.add(upload);
    final error = errors[method];
    if (error != null) {
      upload.failWith(error);
    } else if (into.contains(name)) {
      // Never overwrites, like the real one.
      upload.fail(AdminErrorKind.alreadyExists);
    } else if (autoCompleteUploads) {
      upload.complete();
    }
    return upload;
  }

  @override
  Future<List<String>?> homePhotoNames() async {
    calls.add('homePhotoNames()');
    _fail('homePhotoNames');
    final names = homeNames;
    return names == null ? null : [...names];
  }

  @override
  Future<void> saveHomePhotos(List<String> names) async {
    await _write('saveHomePhotos', 'saveHomePhotos(${names.join(', ')})');
    homeNames = [...names];
  }
}

/// [home] inside a MaterialApp, with [AppServices] backed by fakes.
Widget testApp({
  required AuthService auth,
  BookingService? bookings,
  GalleryService? gallery,
  PortfolioService? portfolio,
  AdminService? admin,
  FakeUrlOpener? urlOpener,
  PickPhotos? pickPhotos,
  bool isEmbeddedBrowser = false,
  Brightness brightness = Brightness.light,
  Map<String, WidgetBuilder> routes = const {},
  required Widget home,
}) {
  return AppServices(
    auth: auth,
    bookings: bookings ?? FakeBookingService(),
    gallery: gallery ?? FakeGalleryService(),
    portfolio: portfolio ?? FakePortfolioService(),
    admin: admin ?? FakeAdminService(),
    openUrl: (urlOpener ?? FakeUrlOpener()).call,
    pickPhotos: pickPhotos ?? FakePhotoPicker().call,
    isEmbeddedBrowser: isEmbeddedBrowser,
    child: MaterialApp(theme: brookieTheme(brightness), routes: routes, home: home),
  );
}
