import 'package:brookie_babies/pages/checkout_page.dart';
import 'package:brookie_babies/pages/home_page.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/firebase_options.dart';

import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';


Map<String, Widget Function(BuildContext)> routes = {
  '/schedule': (context) => const SchedulingPage(packageName: '',),
  '/checkout': (context) => const CheckoutPage(clientSecret: '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'),
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
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      routes: routes,
      theme: theme,
      home: HomePage(),
    );
  }
}
