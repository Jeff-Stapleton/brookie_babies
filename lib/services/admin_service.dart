import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/models/picked_photo.dart';
import 'package:brookie_babies/models/session_details.dart';
import 'package:brookie_babies/models/session_lookup.dart';
import 'package:brookie_babies/models/stored_photo.dart';
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

  /// Adds an ad hoc session; returns its id.
  Future<String> createSession(SessionDetails details);

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
///
/// Not built yet: the admin portal's second phase implements each method.
/// Until then they throw, which StoragePortfolioService treats like a
/// missing `site/home` (it lists the folder instead).
class FirebaseAdminService implements AdminService {
  FirebaseAdminService(this.firestore, this.storage, this.auth);

  final FirebaseFirestore firestore;
  final FirebaseStorage storage;

  /// For the signed-in admin's uid (`createdBy`, `updatedBy`).
  final FirebaseAuth auth;

  @override
  Stream<AllSessions> watchSessions() => throw UnimplementedError();

  @override
  Stream<SessionLookup> watchSession(String id) => throw UnimplementedError();

  @override
  Future<String> createSession(SessionDetails details) => throw UnimplementedError();

  @override
  Future<void> updateSession(Booking session, SessionDetails details) => throw UnimplementedError();

  @override
  Future<void> setPhotosReady(String id, bool ready) => throw UnimplementedError();

  @override
  Future<void> deleteSession(String id) => throw UnimplementedError();

  @override
  Future<List<StoredPhoto>> listSessionPhotos(String id) => throw UnimplementedError();

  @override
  PhotoUpload uploadSessionPhoto(String sessionId, PickedPhoto photo, String name) => throw UnimplementedError();

  @override
  Future<void> deletePhoto(StoredPhoto photo) => throw UnimplementedError();

  @override
  Future<List<StoredPhoto>> listHomeLibrary() => throw UnimplementedError();

  @override
  PhotoUpload uploadToHomeLibrary(PickedPhoto photo, String name) => throw UnimplementedError();

  @override
  Future<List<String>?> homePhotoNames() => throw UnimplementedError();

  @override
  Future<void> saveHomePhotos(List<String> names) => throw UnimplementedError();
}
