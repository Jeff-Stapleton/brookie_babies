// Smoke test for the pricing section of the home page.
//
// It pumps the Packages section on its own, so it needs neither Firebase nor
// the web-only checkout page, and runs on the default (VM) test platform.

import 'package:brookie_babies/components/packages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Packages shows the three pricing cards', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: Packages()),
        ),
      ),
    );

    for (final title in ['Basic', 'Premium', 'Ultimate']) {
      expect(find.text(title), findsOneWidget);
    }
    for (final price in [r'$25', r'$50', r'$99']) {
      expect(find.text(price), findsOneWidget);
    }
    expect(find.widgetWithText(ElevatedButton, 'Book Now'), findsNWidgets(3));
  });
}
