import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:flutter/widgets.dart';

/// Opens [url]. url_launcher's `launchUrl` matches this type.
typedef OpenUrl = Future<bool> Function(Uri url, {String? webOnlyWindowName});

/// Makes app-wide services available to widgets below it. `main.dart` creates
/// the real services; tests pass fakes.
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.auth,
    required this.bookings,
    required this.gallery,
    required this.openUrl,
    this.isEmbeddedBrowser = false,
    required super.child,
  });

  final AuthService auth;
  final BookingService bookings;
  final GalleryService gallery;
  final OpenUrl openUrl;

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
      openUrl != oldWidget.openUrl ||
      isEmbeddedBrowser != oldWidget.isEmbeddedBrowser;
}
