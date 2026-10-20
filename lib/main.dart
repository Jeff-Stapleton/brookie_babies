import 'dart:js_interop';

import 'package:brookie_babies/pages/admin_page.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/firebase_options.dart';
import 'package:brookie_babies/services/admin_service.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/services/portfolio_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/embedded_browser.dart';
import 'package:brookie_babies/utilities/leave_warning.dart';
import 'package:brookie_babies/utilities/web_photo_picker.dart' as web_photo_picker;
import 'package:brookie_babies/widgets/focus_ring.dart';

import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;


Map<String, Widget Function(BuildContext)> routes = {
  '/schedule': (context) => const SchedulingPage(packageName: '',),
  // "Your sessions", also linkable as https://brookie-babies.web.app/#/profile.
  '/profile': (context) => const ProfilePage(),
  AdminPage.routeName: (context) => const AdminPage(),
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  _warnBeforeLeaving();
  final admin = FirebaseAdminService(FirebaseFirestore.instance, FirebaseStorage.instance, FirebaseAuth.instance);
  runApp(MyApp(
    auth: FirebaseAuthService(FirebaseAuth.instance),
    bookings: FirestoreBookingService(FirebaseFirestore.instance),
    // The functions are deployed to us-central1 (functions/src/index.ts).
    gallery: FunctionsGalleryService(FirebaseFunctions.instanceFor(region: 'us-central1')),
    // The photos an admin chose, in order; until then, the gallery by name.
    portfolio: StoragePortfolioService(FirebaseStorage.instance, homePhotoNames: admin.homePhotoNames),
    admin: admin,
    pickPhotos: web_photo_picker.pickPhotos,
    isEmbeddedBrowser: isEmbeddedBrowser(web.window.navigator.userAgent),
  ));
}

/// While [LeaveWarning] is active (uploads running, changes unsaved), the
/// browser asks before the tab closes or reloads. The listener is only
/// there while it's needed: any `beforeunload` listener stops the browser
/// keeping the page for a quick back and forward.
void _warnBeforeLeaving() {
  final ask = ((web.BeforeUnloadEvent event) {
    event.preventDefault();
    // Older browsers ask only when this is set (they show their own words).
    event.returnValue = 'Leave the site?';
  }).toJS;
  LeaveWarning.active.addListener(() {
    if (LeaveWarning.active.value) {
      web.window.addEventListener('beforeunload', ask);
    } else {
      web.window.removeEventListener('beforeunload', ask);
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.auth,
    required this.bookings,
    required this.gallery,
    required this.portfolio,
    required this.admin,
    required this.pickPhotos,
    required this.isEmbeddedBrowser,
  });

  final AuthService auth;
  final BookingService bookings;
  final GalleryService gallery;
  final PortfolioService portfolio;
  final AdminService admin;
  final PickPhotos pickPhotos;
  final bool isEmbeddedBrowser;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return AppServices(
      auth: auth,
      bookings: bookings,
      gallery: gallery,
      portfolio: portfolio,
      admin: admin,
      openUrl: launchUrl,
      pickPhotos: pickPhotos,
      isEmbeddedBrowser: isEmbeddedBrowser,
      child: MaterialApp(
        title: 'Brooke Stapleton Photography',
        // Paper, for the browser's theme color and the app switcher.
        color: BrookieColors.light.paper,
        routes: routes,
        // Print by default; Darkroom when the device asks for dark.
        theme: brookieTheme(Brightness.light),
        darkTheme: brookieTheme(Brightness.dark),
        // Tab and the arrow keys scroll the focused control well into view,
        // so its focus ring is never cut off at the window's edge.
        builder: (context, child) => FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(requestFocusCallback: requestFocusInView),
          child: child!,
        ),
        home: const HomePage(),
      ),
    );
  }
}
