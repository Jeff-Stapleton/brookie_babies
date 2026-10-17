import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/firebase_options.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/services/booking_service.dart';
import 'package:brookie_babies/services/gallery_service.dart';
import 'package:brookie_babies/utilities/embedded_browser.dart';

import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;


Map<String, Widget Function(BuildContext)> routes = {
  '/schedule': (context) => const SchedulingPage(packageName: '',),
  // "My sessions", also linkable as https://brookie-babies.web.app/#/profile.
  '/profile': (context) => const ProfilePage(),
};

ThemeData theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
  useMaterial3: true,
);

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
    isEmbeddedBrowser: isEmbeddedBrowser(web.window.navigator.userAgent),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.auth,
    required this.bookings,
    required this.gallery,
    required this.isEmbeddedBrowser,
  });

  final AuthService auth;
  final BookingService bookings;
  final GalleryService gallery;
  final bool isEmbeddedBrowser;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return AppServices(
      auth: auth,
      bookings: bookings,
      gallery: gallery,
      openUrl: launchUrl,
      isEmbeddedBrowser: isEmbeddedBrowser,
      child: MaterialApp(
        title: 'Flutter Demo',
        routes: routes,
        theme: theme,
        home: HomePage(),
      ),
    );
  }
}
