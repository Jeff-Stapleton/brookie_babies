import 'package:brookie_babies/models/picked_photo.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/services/portfolio_service.dart';
import 'package:flutter/widgets.dart';

/// Opens [url]. url_launcher's `launchUrl` matches this type.
typedef OpenUrl = Future<bool> Function(Uri url, {String? webOnlyWindowName});

/// Opens the browser's file picker for photos whose type matches [accept]
/// (an `<input accept>` value, e.g. 'image/jpeg,image/png,image/webp').
/// Completes with the chosen files, or none if the admin cancels.
///
/// Call it first thing in a tap handler, before any `await`, or the browser
/// may refuse to open the picker. Older browsers never report a cancel, so
/// never wait on it with the page blocked.
typedef PickPhotos = Future<List<PickedPhoto>> Function({required String accept});

/// Makes app-wide services available to widgets below it. `main.dart` creates
/// the real services; tests pass fakes.
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.auth,
    required this.bookings,
    required this.gallery,
    required this.portfolio,
    required this.admin,
    required this.openUrl,
    required this.pickPhotos,
    this.isEmbeddedBrowser = false,
    required super.child,
  });

  final AuthService auth;
  final BookingService bookings;
  final GalleryService gallery;

  /// The home page's photographs.
  final PortfolioService portfolio;

  /// Sessions and photos, for admins.
  final AdminService admin;

  final OpenUrl openUrl;

  final PickPhotos pickPhotos;

  /// True in in-app browsers (Instagram, Facebook, ...) where Google blocks
  /// sign-in.
  final bool isEmbeddedBrowser;

  /// The services don't change while the app runs, so this doesn't register a
  /// rebuild dependency and is safe to call from event handlers.
  static AppServices of(BuildContext context) {
    final services = context.getInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'No AppServices above this widget.');
    return services!;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) =>
      auth != oldWidget.auth ||
      bookings != oldWidget.bookings ||
      gallery != oldWidget.gallery ||
      portfolio != oldWidget.portfolio ||
      admin != oldWidget.admin ||
      openUrl != oldWidget.openUrl ||
      pickPhotos != oldWidget.pickPhotos ||
      isEmbeddedBrowser != oldWidget.isEmbeddedBrowser;
}
