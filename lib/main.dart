import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/firebase_options.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/services/portfolio_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/embedded_browser.dart';

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
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp(
    auth: FirebaseAuthService(FirebaseAuth.instance),
    bookings: FirestoreBookingService(FirebaseFirestore.instance),
    // The functions are deployed to us-central1 (functions/src/index.ts).
    gallery: FunctionsGalleryService(FirebaseFunctions.instanceFor(region: 'us-central1')),
    portfolio: StoragePortfolioService(FirebaseStorage.instance),
    isEmbeddedBrowser: isEmbeddedBrowser(web.window.navigator.userAgent),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.auth,
    required this.bookings,
    required this.gallery,
    required this.portfolio,
    required this.isEmbeddedBrowser,
  });

  final AuthService auth;
  final BookingService bookings;
  final GalleryService gallery;
  final PortfolioService portfolio;
  final bool isEmbeddedBrowser;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return AppServices(
      auth: auth,
      bookings: bookings,
      gallery: gallery,
      portfolio: portfolio,
      openUrl: launchUrl,
      isEmbeddedBrowser: isEmbeddedBrowser,
      child: MaterialApp(
        title: 'Brooke Stapleton Photography',
        // Paper, for the browser's theme color and the app switcher.
        color: BrookieColors.light.paper,
        routes: routes,
        // Print by default; Darkroom when the device asks for dark.
        theme: brookieTheme(Brightness.light),
        darkTheme: brookieTheme(Brightness.dark),
        home: const HomePage(),
      ),
    );
  }
}
