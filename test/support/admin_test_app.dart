// Pumping the admin session pages in widget tests: a signed-in admin, the
// fake admin service and photo picker, a window size, a theme and a text
// size.

import 'package:brookie_babies/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const studio = AppUser(uid: 'studio', email: 'studio@example.com', displayName: 'Brooke');

/// Every width an admin page must fit.
const adminTestWidths = [320.0, 390.0, 1440.0];

/// Pumps [page] (with [routes] for anything it opens by name) for [auth],
/// a signed-in admin by default, in a [size] window.
Future<void> pumpAdminPage(
  WidgetTester tester,
  Widget page, {
  FakeAdminService? admin,
  FakePhotoPicker? picker,
  FakeAuthService? auth,
  Brightness brightness = Brightness.light,
  Size size = const Size(1440, 900),
  double? textScale,
  Map<String, WidgetBuilder> routes = const {},
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(testApp(
    auth: auth ?? FakeAuthService(signedInAs: studio, admin: true),
    admin: admin ?? FakeAdminService(),
    pickPhotos: (picker ?? FakePhotoPicker()).call,
    brightness: brightness,
    routes: routes,
    home: page,
  ));
  if (settle) await tester.pumpAndSettle();
}

/// The real Jost and Newsreader, for tests where text widths decide the
/// layout (the test font sets every glyph a full em wide).
Future<void> loadBrookieFonts() async {
  final jost = FontLoader('Jost');
  for (final weight in ['Light', 'Regular', 'Medium']) {
    jost.addFont(rootBundle.load('assets/fonts/Jost-$weight.ttf'));
  }
  final newsreader = FontLoader('Newsreader')
    ..addFont(rootBundle.load('assets/fonts/Newsreader-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Newsreader-LightItalic.ttf'));
  await Future.wait([jost.load(), newsreader.load()]);
}

/// Whether the widget holding [finder] (a button's label, say) has keyboard
/// focus.
bool hasFocus(WidgetTester tester, Finder finder) => Focus.of(tester.element(finder)).hasPrimaryFocus;

/// Taps [finder] after scrolling it into view.
Future<void> tapInView(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

/// Every [FilledButton] (the view's primary button) on screen.
int filledButtons() => find.byType(FilledButton).evaluate().length;

/// The [Text] showing who a session is for: [name] itself, or an email set
/// with places to break (it carries [name] as its semantics label).
Finder findDisplayName(String name) =>
    find.byWidgetPredicate((widget) => widget is Text && (widget.data == name || widget.semanticsLabel == name));
