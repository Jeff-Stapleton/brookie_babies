import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/firebase_options.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/utilities/embedded_browser.dart';

import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;


Map<String, Widget Function(BuildContext)> routes = {
  '/schedule': (context) => const SchedulingPage(packageName: '',),
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
    isEmbeddedBrowser: isEmbeddedBrowser(web.window.navigator.userAgent),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.auth, required this.isEmbeddedBrowser});

  final AuthService auth;
  final bool isEmbeddedBrowser;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return AppServices(
      auth: auth,
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
