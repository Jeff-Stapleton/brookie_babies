import 'dart:async';
import 'dart:developer';

import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/picked_photo.dart';
import 'package:brookie_babies/models/session_details.dart';
import 'package:brookie_babies/models/session_lookup.dart';
import 'package:brookie_babies/models/stored_photo.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/services/photo_rules.dart';
import 'package:brookie_babies/services/portfolio_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Every session in `bookings`, plus the documents that couldn't be read, so
/// the admin page can name them instead of silently leaving them out.
typedef AllSessions = ({List<Booking> sessions, List<UnreadableBooking> unreadable});

/// Why an [AdminService] call failed.
enum AdminErrorKind { denied, offline, notFound, cancelled, alreadyExists, quota, invalid, unknown }

/// Thrown by [AdminService] with a message to show the admin.
class AdminException implements Exception {
  const AdminException(this.message, [this.kind = AdminErrorKind.unknown]);

  final String message;
  final AdminErrorKind kind;

  @override
  String toString() => message;
}

/// [AdminErrorKind.denied]: the rules said no, which (since the app checks
/// every rule first) means the admin claim is missing or not yet in the
/// token.
const kAdminDeniedMessage =
    'We couldn’t save that change. If you were just made an admin, refresh the page and try again.';

/// [AdminErrorKind.offline].
const kAdminOfflineMessage = 'We couldn’t reach the server. Check your connection and try again.';

/// [AdminErrorKind.quota].
const kAdminQuotaMessage = 'Storage is full. Delete photos you no longer need, or upgrade the Firebase plan.';

/// [AdminErrorKind.offline] for a write that got no answer in time: it may
/// still reach the server, so trying again could make it twice.
const kAdminTimedOutMessage =
    'We couldn’t reach the server in time. Your change may still be saved: refresh the page to check.';

/// One photo on its way to Storage.
abstract class PhotoUpload {
  /// 0–1: how much has been sent (0 until the size is known).
  ValueListenable<double> get progress;

  /// Completes when the photo is stored, or fails with an [AdminException]
  /// ([AdminErrorKind.cancelled] after [cancel]).
  Future<void> get done;

  void cancel();
}

/// What admins do: add and edit ad hoc sessions, upload and delete session
/// photos, make them available, and choose the home page photos.
/// [FirebaseAdminService] is the real implementation; tests use a fake.
///
/// Every write is checked against lib/services/photo_rules.dart (the rules'
/// mirror) first, so a rule rejection only ever means an access problem.
/// Failures throw [AdminException].
abstract class AdminService {
  /// Every session, updated live, in no particular order.
  Stream<AllSessions> watchSessions();

  /// The session [id], updated live.
  Stream<SessionLookup> watchSession(String id);

  /// An id for a new session, made without writing anything.
  String newSessionId();

  /// Adds an ad hoc session as [id] (from [newSessionId]; a new one if
  /// null) and returns its id. Trying again with the same id never makes a
  /// second session: a try that got no answer may still have been saved, and
  /// a retry then finds it and returns its id.
  Future<String> createSession(SessionDetails details, {String? id});

  /// Changes an ad hoc session's details.
  Future<void> updateSession(Booking session, SessionDetails details);

  /// Lets the family download the photos, or stops them.
  Future<void> setPhotosReady(String id, bool ready);

  /// Deletes an ad hoc session: hides its photos, deletes them (in
  /// subfolders too) and their cached zip, then the document.
  Future<void> deleteSession(String id);

  /// Every photo in the session's folder, subfolders included, sorted by
  /// [StoredPhoto.name] (relative to the folder). Leaves out folder markers
  /// (names ending in '/') and hidden files (basenames starting with '.').
  /// Session photos never get a [StoredPhoto.url].
  Future<List<StoredPhoto>> listSessionPhotos(String id);

  /// Uploads [photo] into the session's folder as [name], a
  /// PhotoRules.safeObjectName. Never overwrites: a photo already there
  /// fails with [AdminErrorKind.alreadyExists].
  PhotoUpload uploadSessionPhoto(String sessionId, PickedPhoto photo, String name);

  /// Deletes one photo. One that's already gone counts as deleted.
  Future<void> deletePhoto(StoredPhoto photo);

  /// Every file directly in the public `_admin/gallery` folder, with a
  /// [StoredPhoto.url] for the ones the site can show
  /// (StoragePortfolioService.isPhoto).
  Future<List<StoredPhoto>> listHomeLibrary();

  /// Uploads [photo] into the home page library as [name], like
  /// [uploadSessionPhoto].
  PhotoUpload uploadToHomeLibrary(PickedPhoto photo, String name);

  /// The home page photos chosen in `site/home`, in order (the first is the
  /// hero), or null if none were ever chosen.
  Future<List<String>?> homePhotoNames();

  /// Saves [names] (files in the library, at most PhotoRules.homeMaxPhotos)
  /// as the home page photos.
  Future<void> saveHomePhotos(List<String> names);
}

/// [AdminService] on Firestore and Storage, writing straight from the
/// browser; firestore.rules and storage.rules only let admins do it.
/// [newSessionData], [sessionChanges] and PhotoRules check what the rules
/// check before anything is sent.
class FirebaseAdminService implements AdminService {
  FirebaseAdminService(this.firestore, this.storage, this.auth, {this.writeTimeLimit = const Duration(seconds: 20)});

  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  /// For the signed-in admin's uid (`createdBy`, `updatedBy`).
  final FirebaseAuth auth;

  /// How long a Firestore write may take before the admin is told it may
  /// not have been saved: offline, the web SDK waits for the server with no
  /// limit, which would leave the page waiting for good.
  final Duration writeTimeLimit;

  /// How many Storage requests a listing or deletion has going at once.
  static const storageConcurrency = 6;

  static const _galleries = 'galleries';

  CollectionReference<Map<String, dynamic>> get _bookings => firestore.collection('bookings');

  DocumentReference<Map<String, dynamic>> get _home => firestore.doc('site/home');

  @override
  Stream<AllSessions> watchSessions() => _reading(
        'list the sessions',
        _bookings.snapshots().map((snapshot) => _sessionsFrom([
              for (final doc in snapshot.docs) (id: doc.id, data: doc.data()),
            ])),
      );

  @override
  Stream<SessionLookup> watchSession(String id) => _reading(
        'watch session $id',
        _bookings.doc(id).snapshots().map((doc) => _sessionLookupFrom(doc.id, doc.data())),
      );

  @override
  String newSessionId() => _bookings.doc().id;

  @override
  Future<String> createSession(SessionDetails details, {String? id}) async {
    _check(sessionDetailsProblem(details));
    final uid = _signedInUid();
    // The id is made here, not by add(), so it's known before the server
    // answers and a retry can use it again.
    final doc = _bookings.doc(id == null ? newSessionId() : _sessionId(id));
    try {
      await _write('add a session', () => doc.set(newSessionData(details, createdBy: uid)));
    } on AdminException catch (e) {
      // A retry after a try that got no answer but was saved: the rules
      // take set() on a document that's there as an update, and refuse it.
      if (id == null || e.kind != AdminErrorKind.denied || !await _exists(doc)) rethrow;
    }
    return doc.id;
  }

  @override
  Future<void> updateSession(Booking session, SessionDetails details) async {
    if (!session.isAdHoc) {
      throw const AdminException(
        'Only ad hoc sessions can be edited here. Change a booking’s details in the Firestore console.',
        AdminErrorKind.invalid,
      );
    }
    _check(sessionDetailsProblem(details));
    _signedInUid();
    final changes = sessionChanges(session, details);
    if (changes.isEmpty) return;
    await _write(
      'edit session ${session.id}',
      () => _bookings.doc(session.id).update({...changes, 'updatedAt': FieldValue.serverTimestamp()}),
    );
  }

  @override
  Future<void> setPhotosReady(String id, bool ready) async {
    _signedInUid();
    await _write(
      'set photosReady on session $id',
      () => _bookings.doc(id).update({'photosReady': ready, 'updatedAt': FieldValue.serverTimestamp()}),
    );
  }

  @override
  Future<void> deleteSession(String id) async {
    _signedInUid();
    final folder = _galleryPath(id);
    final doc = _bookings.doc(id);
    final data = (await _attempt('read session $id', _Doing.writing, doc.get)).data();
    // Already gone: a retry after a failure part way, or another tab. The
    // rules would refuse deleting it again.
    if (data == null) return;
    if (data['status'] != BookingStatus.adhoc.name) {
      throw const AdminException(
        'Only ad hoc sessions can be deleted. A booking is the record of a payment, so it stays.',
        AdminErrorKind.invalid,
      );
    }
    // Hidden first, so nobody downloads a half-deleted gallery, and a
    // failure part way leaves it hidden rather than broken.
    if (data['photosReady'] == true) {
      await _write(
        'hide the photos of session $id',
        () => doc.update({'photosReady': false, 'updatedAt': FieldValue.serverTimestamp()}),
      );
    }
    await _attempt('delete the photos of session $id', _Doing.writing, () async {
      // Everything, hidden files included: the folder goes with the session.
      await _forEachLimited(await _listAllUnder(storage.ref(folder)), _deleteIfThere);
      // Admins may delete the cached zip but not look it up, so it goes by
      // name.
      await _deleteIfThere(storage.ref('gallery-zips/$id.zip'));
    });
    await _write('delete session $id', doc.delete);
  }

  @override
  Future<List<StoredPhoto>> listSessionPhotos(String id) async {
    final folder = _galleryPath(id);
    final files =
        await _attempt('list the photos of session $id', _Doing.reading, () => _listAllUnder(storage.ref(folder)));
    final prefix = '$folder/';
    final photos = <StoredPhoto>[];
    for (final file in files) {
      if (!file.fullPath.startsWith(prefix)) continue;
      final name = file.fullPath.substring(prefix.length);
      // What getGalleryDownloadUrl zips (functions/src/gallery.ts,
      // selectPhotos), so the count here is the count families get.
      final basename = name.split(RegExp(r'[\\/]')).last;
      if (name.endsWith('/') || basename.isEmpty || basename.startsWith('.')) continue;
      photos.add(StoredPhoto(name: name, fullPath: file.fullPath));
    }
    // By UTF-16 code unit, as the function sorts the zip.
    return photos..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  PhotoUpload uploadSessionPhoto(String sessionId, PickedPhoto photo, String name) => _upload(
        photo,
        name,
        problem: PhotoRules.sessionPhotoProblem(photo) ?? _nameProblem(name),
        target: () => storage.ref('${_galleryPath(sessionId)}/$name'),
      );

  @override
  Future<void> deletePhoto(StoredPhoto photo) async {
    _signedInUid();
    await _attempt('delete ${photo.fullPath}', _Doing.writing, () => _deleteIfThere(storage.ref(photo.fullPath)));
  }

  @override
  Future<List<StoredPhoto>> listHomeLibrary() async {
    const folder = StoragePortfolioService.folder;
    final listing = await _attempt('list the home page library', _Doing.reading, () => storage.ref(folder).listAll());
    final files = [...listing.items]..sort((a, b) => a.name.compareTo(b.name));
    final urls = <String, Uri>{};
    await _forEachLimited(files.where((file) => StoragePortfolioService.isPhoto(file.name)), (file) async {
      // A link that can't be fetched leaves that photo without a thumbnail,
      // not the library without its list.
      try {
        urls[file.fullPath] = Uri.parse(await file.getDownloadURL());
      } catch (e) {
        log('Admin: could not get a link for library photo ${file.name}: $e');
      }
    });
    return [
      for (final file in files) StoredPhoto(name: file.name, fullPath: file.fullPath, url: urls[file.fullPath]),
    ];
  }

  @override
  PhotoUpload uploadToHomeLibrary(PickedPhoto photo, String name) => _upload(
        photo,
        name,
        // storage.rules checks the stored name's ending as well as the type.
        problem: PhotoRules.homePhotoProblem(photo) ??
            _nameProblem(name) ??
            (StoragePortfolioService.isPhoto(name)
                ? null
                : '$name needs a .jpg, .png or .webp ending. Rename it and upload it again.'),
        target: () => storage.ref('${StoragePortfolioService.folder}/$name'),
      );

  @override
  Future<List<String>?> homePhotoNames() => _attempt('read the home page photos', _Doing.reading, () async {
        final photos = (await _home.get()).data()?['photos'];
        // Null: none chosen yet (no document), so the site lists the library.
        if (photos is! List) return null;
        return [
          for (final name in photos)
            if (name is String) name,
        ];
      });

  @override
  Future<void> saveHomePhotos(List<String> names) async {
    _check(_homePhotosProblem(names));
    final uid = _signedInUid();
    // The whole document, exactly the keys firestore.rules allows for
    // site/home.
    await _write(
      'save the home page photos',
      () => _home.set({
        'photos': [...names],
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid
      }),
    );
  }

  PhotoUpload _upload(
    PickedPhoto photo,
    String name, {
    required String? problem,
    required Reference Function() target,
  }) {
    if (problem != null) return _StorageUpload.failed(AdminException(problem, AdminErrorKind.invalid));
    if (auth.currentUser == null) return _StorageUpload.failed(_signedOut);
    try {
      return _StorageUpload.start(target(), photo.data, PhotoRules.contentTypeFor(photo)!);
    } catch (e) {
      return _StorageUpload.failed(_failure('upload $name', e, _Doing.uploading));
    }
  }

  /// [id], if it's a session id that can't reach another document or
  /// folder.
  static String _sessionId(String id) {
    // An empty id would make it every family's photos.
    if (id.isEmpty || id.contains('/') || id == '.' || id == '..') {
      throw ArgumentError.value(id, 'id', 'Not a session id');
    }
    return id;
  }

  /// `galleries/<id>`, for a session id that can't reach another folder.
  static String _galleryPath(String id) => '$_galleries/${_sessionId(id)}';

  /// Whether [doc] is there; false if that can't be read either.
  static Future<bool> _exists(DocumentReference<Map<String, dynamic>> doc) async {
    try {
      return (await doc.get()).exists;
    } catch (e) {
      log('Admin: could not read ${doc.path}: $e');
      return false;
    }
  }

  static String? _nameProblem(String name) => name == PhotoRules.safeObjectName(name)
      ? null
      : '$name can’t be used as a file name. Rename it and upload it again.';

  static String? _homePhotosProblem(List<String> names) {
    if (names.length > PhotoRules.homeMaxPhotos) {
      return 'The home page shows at most ${PhotoRules.homeMaxPhotos} photos. Remove one and save again.';
    }
    for (final name in names) {
      // Files directly in the library. `photos` is a plain list, so the
      // rules can't check what's in it.
      if (name.isEmpty || name.contains('/')) {
        return '“$name” isn’t a photo in the library. Refresh the page and choose again.';
      }
    }
    return null;
  }

  static void _check(String? problem) {
    if (problem != null) throw AdminException(problem, AdminErrorKind.invalid);
  }

  static const _signedOut = AdminException(
    'You’re signed out. Sign in with the studio’s Google account and try again.',
    AdminErrorKind.denied,
  );

  String _signedInUid() {
    final user = auth.currentUser;
    if (user == null) throw _signedOut;
    return user.uid;
  }

  /// Runs a Firestore write, giving up on it after [writeTimeLimit].
  Future<void> _write(String what, Future<void> Function() write) => _attempt(
        what,
        _Doing.writing,
        () => write().timeout(writeTimeLimit, onTimeout: () {
          log('Admin: no answer in ${writeTimeLimit.inSeconds} s when trying to $what');
          throw const AdminException(kAdminTimedOutMessage, AdminErrorKind.offline);
        }),
      );

  /// [run], with any failure as an [AdminException].
  static Future<T> _attempt<T>(String what, _Doing doing, Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw _failure(what, e, doing);
    }
  }

  /// [stream], with its errors as [AdminException]s.
  static Stream<T> _reading<T>(String what, Stream<T> stream) => stream.transform(
        StreamTransformer<T, T>.fromHandlers(
          handleError: (error, stackTrace, sink) => sink.addError(_failure(what, error, _Doing.reading), stackTrace),
        ),
      );
}

/// What the admin was doing when something failed, for the message.
enum _Doing {
  reading(
    denied: 'We couldn’t load this. If you were just made an admin, refresh the page and try again.',
    failed: 'We couldn’t load this. Refresh the page to try again.',
  ),
  writing(denied: kAdminDeniedMessage, failed: _writeFailedMessage),
  uploading(denied: kAdminDeniedMessage, failed: 'This photo didn’t upload. Try again.');

  const _Doing({required this.denied, required this.failed});

  final String denied;
  final String failed;
}

const _writeFailedMessage = 'We couldn’t save that change. Refresh the page and try again.';

/// Logs [error] (never with an email: [what] names ids and paths only) and
/// returns it as an [AdminException].
AdminException _failure(String what, Object error, _Doing doing) {
  if (error is AdminException) return error;
  log('Admin: could not $what: $error');
  return adminExceptionFrom(error, denied: doing.denied, failed: doing.failed);
}

/// A Firebase error's code without the web SDKs' prefix
/// ('storage/unauthorized' is 'unauthorized'), or null for anything else.
String? _codeOf(Object error) => error is FirebaseException ? error.code.split('/').last : null;

/// [error] from Firestore or Storage as an [AdminException], with a message
/// for the admin: [denied] when the rules refuse, [failed] when nothing more
/// useful can be said.
@visibleForTesting
AdminException adminExceptionFrom(
  Object error, {
  String denied = kAdminDeniedMessage,
  String failed = _writeFailedMessage,
}) {
  if (error is AdminException) return error;
  if (error is TimeoutException) return const AdminException(kAdminOfflineMessage, AdminErrorKind.offline);
  // Firestore's codes and Storage's (as the web SDK reports them) never mean
  // different things by the same name, so one switch serves both.
  return switch (_codeOf(error)) {
    'permission-denied' || 'unauthenticated' || 'unauthorized' => AdminException(denied, AdminErrorKind.denied),
    'unavailable' ||
    'deadline-exceeded' ||
    'retry-limit-exceeded' =>
      const AdminException(kAdminOfflineMessage, AdminErrorKind.offline),
    'not-found' || 'object-not-found' => const AdminException(
        'That’s no longer there. Refresh the page to see what’s there now.',
        AdminErrorKind.notFound,
      ),
    'cancelled' || 'canceled' => const AdminException(_cancelledMessage, AdminErrorKind.cancelled),
    'quota-exceeded' => const AdminException(kAdminQuotaMessage, AdminErrorKind.quota),
    _ => AdminException(failed),
  };
}

const _cancelledMessage = 'Cancelled before it finished. Try again.';

/// Why firestore.rules would refuse an ad hoc session with [details] (its
/// validName, validEmail, validDate, ... functions), written for the admin;
/// null if it wouldn't. Change the two together.
@visibleForTesting
String? sessionDetailsProblem(SessionDetails details) {
  final name = details.name.trim();
  if (name.isEmpty) return 'Enter who the session is for, like “The Harper family”.';
  if (name.length > SessionRules.nameMaxLength) {
    return 'The name is too long. Shorten it to ${SessionRules.nameMaxLength} characters or fewer.';
  }
  if (!SessionRules.emailPattern.hasMatch(SessionRules.normalizeEmail(details.email))) {
    return 'That email doesn’t look right. Enter the Google email they sign in with, like name@gmail.com.';
  }
  final packageName = _optional(details.packageName);
  if (packageName != null && !SessionRules.packageNames.contains(packageName)) {
    return 'That package doesn’t exist. Choose ${SessionRules.packageNames.join(', ')} or no package.';
  }
  // YYYY-MM-DD needs a four-digit year.
  if (details.date.year < 0 || details.date.year > 9999) {
    return 'That date can’t be saved. Choose a date from the calendar.';
  }
  final time = details.time;
  if (time != null && (time.hour < 0 || time.hour > 23 || time.minute < 0 || time.minute > 59)) {
    return 'That time can’t be saved. Choose a time from the list.';
  }
  final location = _optional(details.location);
  if (location != null && location.length > SessionRules.locationMaxLength) {
    return 'The location is too long. Shorten it to ${SessionRules.locationMaxLength} characters or fewer.';
  }
  return null;
}

/// The `bookings` document for a new ad hoc session: exactly the keys
/// firestore.rules lets an admin create, with the optional ones left out
/// when empty (the rules refuse nulls). Check [sessionDetailsProblem] first.
@visibleForTesting
Map<String, Object> newSessionData(SessionDetails details, {required String createdBy}) {
  final fields = _sessionFields(details);
  return {
    'status': BookingStatus.adhoc.name,
    for (final MapEntry(:key, :value) in fields.entries)
      if (value != null) key: value,
    'photosReady': false,
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': createdBy,
  };
}

/// What [details] change in the ad hoc [session], for update(): only the
/// fields that differ (the rules check only what changes), and
/// FieldValue.delete() for an optional one cleared (the rules refuse
/// nulls). Empty if nothing changed. The caller adds `updatedAt`.
@visibleForTesting
Map<String, Object> sessionChanges(Booking session, SessionDetails details) {
  final before = _fields(
    name: session.name,
    email: session.email,
    packageName: session.packageName,
    date: session.date,
    time: session.time,
    location: session.location,
  );
  return {
    for (final MapEntry(:key, :value) in _sessionFields(details).entries)
      if (value != before[key]) key: value ?? FieldValue.delete(),
  };
}

/// [details] as the document's text fields: name trimmed, email as stored
/// (SessionRules.normalizeEmail), null for an optional field left empty.
Map<String, String?> _sessionFields(SessionDetails details) => _fields(
      name: details.name.trim(),
      email: SessionRules.normalizeEmail(details.email),
      packageName: _optional(details.packageName),
      date: details.date,
      time: details.time,
      location: _optional(details.location),
    );

Map<String, String?> _fields({
  required String? name,
  required String? email,
  required String? packageName,
  required DateTime date,
  required ({int hour, int minute})? time,
  required String? location,
}) {
  String two(int n) => n.toString().padLeft(2, '0');
  return {
    'name': name,
    'email': email,
    'packageName': packageName,
    // YYYY-MM-DD and 24-hour HH:mm, as Booking.fromMap reads them.
    'date': '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}',
    'time': time == null ? null : '${two(time.hour)}:${two(time.minute)}',
    'location': location,
  };
}

String? _optional(String? text) {
  final trimmed = text?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// [docs] as sessions, and the ones [Booking.fromMap] can't read.
AllSessions _sessionsFrom(Iterable<BookingDoc> docs) {
  final sessions = <Booking>[];
  final unreadable = <UnreadableBooking>[];
  for (final doc in docs) {
    final booking = Booking.fromMap(doc.id, doc.data);
    if (booking == null) {
      unreadable.add(_unreadable(doc.id, doc.data));
    } else {
      sessions.add(booking);
    }
  }
  return (sessions: sessions, unreadable: unreadable);
}

/// The `bookings` document [id], from its [data] (null if there is none).
SessionLookup _sessionLookupFrom(String id, Map<String, dynamic>? data) {
  if (data == null) return const SessionMissing();
  final booking = Booking.fromMap(id, data);
  return booking == null ? SessionUnreadable(_unreadable(id, data)) : SessionFound(booking);
}

UnreadableBooking _unreadable(String id, Map<String, dynamic> data) {
  final email = data['email'];
  final date = data['date'];
  return UnreadableBooking(
    id: id,
    problem: Booking.problemWith(data) ?? 'it couldn’t be read',
    email: email is String ? email : null,
    date: date is String ? date : null,
  );
}

/// Every file under [folder], walking its subfolders (Storage lists one
/// level at a time).
Future<List<Reference>> _listAllUnder(Reference folder) async {
  final files = <Reference>[];
  final folders = [folder];
  while (folders.isNotEmpty) {
    final listing = await folders.removeLast().listAll();
    files.addAll(listing.items);
    folders.addAll(listing.prefixes);
  }
  return files;
}

/// Deletes [file]; one that's already gone counts as deleted.
Future<void> _deleteIfThere(Reference file) async {
  try {
    await file.delete();
  } catch (e) {
    if (_codeOf(e) != 'object-not-found') rethrow;
  }
}

/// Runs [action] on each of [items], [FirebaseAdminService.storageConcurrency]
/// at a time. After a failure it starts no more, and rethrows the first
/// failure once the ones running have finished.
Future<void> _forEachLimited<T>(Iterable<T> items, Future<void> Function(T item) action) async {
  final queue = items.iterator;
  Object? failure;
  StackTrace failureTrace = StackTrace.empty;
  Future<void> worker() async {
    while (failure == null && queue.moveNext()) {
      try {
        await action(queue.current);
      } catch (e, stackTrace) {
        if (failure != null) continue;
        failure = e;
        failureTrace = stackTrace;
      }
    }
  }

  await Future.wait([for (var i = 0; i < FirebaseAdminService.storageConcurrency; i++) worker()]);
  final error = failure;
  if (error != null) Error.throwWithStackTrace(error, failureTrace);
}

/// A [PhotoUpload] over a Storage [UploadTask]. [done] settles from the
/// task's own Future; its snapshot events only move [progress].
class _StorageUpload implements PhotoUpload {
  /// One refused before anything was sent.
  _StorageUpload.failed(AdminException error) : _target = null {
    _settled = true;
    _done.completeError(error);
  }

  /// Starts sending [data] to [target] as [contentType]. Never throws: a
  /// failure to start fails [done].
  _StorageUpload.start(Reference target, Object data, String contentType) : _target = target {
    final metadata = SettableMetadata(contentType: contentType);
    final UploadTask task;
    try {
      // On the web [data] is the browser's File, which the plugin needs as
      // it is (a Blob); tests pass bytes.
      task = data is Uint8List ? target.putData(data, metadata) : target.putBlob(data, metadata);
    } catch (e) {
      _settle(e);
      return;
    }
    _task = task;
    task
        .then<void>((_) => _settle(null), onError: (Object e) => _settle(e))
        // Should the plugin fail after the task settles, still settle.
        .catchError((Object e) => _settle(e));
    try {
      // A failure reaches this stream too; the task's Future reports it.
      _events = task.snapshotEvents.listen(_onSnapshot, onError: (Object _) {});
    } catch (e) {
      log('Admin: no upload progress for ${target.fullPath}: $e');
    }
  }

  final Reference? _target;
  UploadTask? _task;
  StreamSubscription<TaskSnapshot>? _events;
  final _progress = ValueNotifier<double>(0);

  // A failure nobody waits for (its page closed, say) isn't reported as
  // uncaught; anyone listening to [done] still gets it.
  final _done = Completer<void>()..future.ignore();
  bool _settled = false;
  bool _cancelled = false;

  @override
  ValueListenable<double> get progress => _progress;

  @override
  Future<void> get done => _done.future;

  @override
  void cancel() {
    final task = _task;
    if (_settled || task == null) return;
    _cancelled = true;
    // The outcome comes through the task's Future: "canceled", or success
    // if the photo got there first.
    try {
      task.cancel().ignore();
    } catch (e) {
      log('Admin: could not cancel the upload to ${_target?.fullPath}: $e');
    }
  }

  void _onSnapshot(TaskSnapshot snapshot) {
    if (_settled) return;
    final total = snapshot.totalBytes;
    _progress.value = total > 0 ? (snapshot.bytesTransferred / total).clamp(0.0, 1.0) : 0;
  }

  Future<void> _settle(Object? error) async {
    if (_settled) return;
    _settled = true;
    unawaited(_events?.cancel());
    if (error == null) {
      _progress.value = 1;
      _done.complete();
    } else {
      _done.completeError(await _explain(error));
    }
  }

  Future<AdminException> _explain(Object error) async {
    // After cancel(), however the task ends counts as cancelled.
    if (_cancelled) return const AdminException(_cancelledMessage, AdminErrorKind.cancelled);
    final target = _target!;
    if (_codeOf(error) == 'unauthorized') {
      // storage.rules never overwrites, so a name taken since the folder
      // was listed (in another tab, say) is refused just like a missing
      // admin claim. An admin may read what they may write, so look.
      try {
        await target.getMetadata();
        return const AdminException(
          'Already here — to replace a photo, delete it first.',
          AdminErrorKind.alreadyExists,
        );
      } catch (e) {
        if (_codeOf(e) != 'object-not-found') log('Admin: could not check ${target.fullPath}: $e');
      }
    }
    return _failure('upload ${target.fullPath}', error, _Doing.uploading);
  }
}
