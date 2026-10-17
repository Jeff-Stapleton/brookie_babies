import 'dart:async';

import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:flutter/material.dart';

const testUser = AppUser(uid: 'uid123', email: 'parent@example.com', displayName: 'Pat Parent');

/// In-memory [AuthService] for widget tests.
class FakeAuthService implements AuthService {
  FakeAuthService({AppUser? signedInAs}) : _user = signedInAs;

  final _changes = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  /// What the next [signInWithGoogle] returns: a user, or null as if the
  /// Google popup was closed.
  AppUser? nextSignIn;

  /// If set, the next [signInWithGoogle] throws it instead.
  SignInException? nextSignInError;

  int signInCalls = 0;

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
  final watchedUids = <String>[];

  @override
  Stream<UserBookings> watchBookings(String uid) {
    watchedUids.add(uid);
    final error = this.error;
    return error == null
        ? Stream.value((bookings: bookings, unreadable: unreadable))
        : Stream.error(error);
  }
}

/// [GalleryService] whose downloads stay pending until the test calls
/// [complete] or [fail].
class FakeGalleryService implements GalleryService {
  final requested = <String>[];

  // Created per call rather than up front, so it belongs to the test's
  // fake-async zone and completing it reaches the widget.
  Completer<GalleryDownload>? _pending;

  @override
  Future<GalleryDownload> prepareDownload(String bookingId) {
    requested.add(bookingId);
    return (_pending = Completer()).future;
  }

  void complete(GalleryDownload download) => _pending!.complete(download);

  void fail(Object error) => _pending!.completeError(error);
}

/// Records the URLs the app opens instead of launching them.
class FakeUrlOpener {
  final opened = <({Uri url, String? windowName})>[];

  Future<bool> call(Uri url, {String? webOnlyWindowName}) async {
    opened.add((url: url, windowName: webOnlyWindowName));
    return true;
  }
}

/// [home] inside a MaterialApp, with [AppServices] backed by fakes.
Widget testApp({
  required AuthService auth,
  BookingService? bookings,
  GalleryService? gallery,
  FakeUrlOpener? urlOpener,
  bool isEmbeddedBrowser = false,
  required Widget home,
}) {
  return AppServices(
    auth: auth,
    bookings: bookings ?? FakeBookingService(),
    gallery: gallery ?? FakeGalleryService(),
    openUrl: (urlOpener ?? FakeUrlOpener()).call,
    isEmbeddedBrowser: isEmbeddedBrowser,
    child: MaterialApp(home: home),
  );
}
