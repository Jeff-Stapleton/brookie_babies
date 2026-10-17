import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:brookie_babies/widgets/google_sign_in_button.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Opens the dialog from a button and keeps what it completes with.
class _Opener extends StatelessWidget {
  const _Opener({required this.onResult, this.toBook = false});

  final void Function(AppUser?) onResult;
  final bool toBook;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElevatedButton(
        onPressed: () async => onResult(await showSignInDialog(context, toBook: toBook)),
        child: const Text('open'),
      ),
    );
  }
}

void main() {
  late FakeAuthService auth;
  AppUser? result;
  var completed = false;

  Future<void> openDialog(
    WidgetTester tester, {
    bool isEmbeddedBrowser = false,
    bool toBook = false,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(testApp(
      auth: auth,
      isEmbeddedBrowser: isEmbeddedBrowser,
      brightness: brightness,
      home: _Opener(
        toBook: toBook,
        onResult: (user) {
          result = user;
          completed = true;
        },
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    auth = FakeAuthService();
    result = null;
    completed = false;
  });

  testWidgets('closes with the user after Google sign-in', (tester) async {
    auth.nextSignIn = testUser;
    await openDialog(tester);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 1);
    expect(find.byType(SignInDialog), findsNothing);
    expect(completed, isTrue);
    expect(result?.uid, testUser.uid);
  });

  testWidgets('stays open when the Google popup is closed', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 1);
    expect(find.byType(SignInDialog), findsOneWidget);
    expect(completed, isFalse);
  });

  testWidgets('shows the error when sign-in fails', (tester) async {
    auth.nextSignInError = const SignInException('Pop-ups are blocked.');
    await openDialog(tester);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InlineMessage, 'Pop-ups are blocked.'), findsOneWidget);
    expect(tester.widget<InlineMessage>(find.byType(InlineMessage)).tone, StatusTone.danger);
    expect(find.byType(SignInDialog), findsOneWidget);
  });

  testWidgets('a retry clears the last error', (tester) async {
    auth.nextSignInError = const SignInException('Pop-ups are blocked.');
    await openDialog(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    auth.nextSignInError = null;
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 2);
    expect(find.byType(InlineMessage), findsNothing);
  });

  testWidgets('focus starts on "Continue with Google"', (tester) async {
    await openDialog(tester);

    expect(Focus.of(tester.element(find.text('Continue with Google'))).hasPrimaryFocus, isTrue);
  });

  for (final toBook in [false, true]) {
    testWidgets('the primary action is Google’s own button${toBook ? ' when signing in to book' : ''}',
        (tester) async {
      await openDialog(tester, toBook: toBook);

      expect(find.widgetWithText(GoogleSignInButton, 'Continue with Google'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      // Not the system's ink button, and no Material icon standing in for the G.
      final surface = tester.widget<Material>(
          find.descendant(of: find.byType(GoogleSignInButton), matching: find.byType(Material)));
      expect(surface.color, isNot(BrookieColors.light.ink));
      expect(find.byIcon(Icons.login), findsNothing);
      final logo = tester.widget<Image>(find.descendant(of: find.byType(GoogleSignInButton), matching: find.byType(Image)));
      expect(logo.image, GoogleSignInButton.logo);
      expect((logo.image as AssetImage).assetName, 'assets/google/g_logo.png');
    });
  }

  testWidgets('Google’s button: the G at 20px and Google’s spacing, on a 52px pill like Cancel', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openDialog(tester);

    final button = tester.getRect(find.byType(GoogleSignInButton));
    final logo = tester.getRect(find.descendant(of: find.byType(GoogleSignInButton), matching: find.byType(Image)));
    final label = tester.getRect(find.text('Continue with Google'));
    // As tall as Cancel, so the two sit level when side by side (the test
    // font is too wide for that here).
    expect(button.height, BrookieSize.control);
    expect(tester.getSize(find.widgetWithText(TextButton, 'Cancel')).height, button.height);
    expect(logo.size, const Size.square(20));
    expect(logo.left - button.left, moreOrLessEquals(12));
    expect(label.left - logo.right, moreOrLessEquals(10));
    expect(button.right - label.right, moreOrLessEquals(12));
    expect(logo.center.dy, moreOrLessEquals(button.center.dy));
    final surface = tester.widget<Material>(
        find.descendant(of: find.byType(GoogleSignInButton), matching: find.byType(Material)));
    expect(surface.shape, isA<StadiumBorder>());
  });

  testWidgets('Google’s button: Roboto Medium at 14px, as Google specifies', (tester) async {
    await openDialog(tester);

    final style = tester.renderObject<RenderParagraph>(find.text('Continue with Google')).text.style!;
    expect(style.fontFamily, 'Roboto');
    expect(style.fontWeight, FontWeight.w500);
    expect(style.fontSize, 14);
  });

  for (final (brightness, fill, edge, label) in [
    (Brightness.light, const Color(0xFFFFFFFF), const Color(0xFF747775), const Color(0xFF1F1F1F)),
    (Brightness.dark, const Color(0xFF131314), const Color(0xFF8E918F), const Color(0xFFE3E3E3)),
  ]) {
    testWidgets('Google’s button takes Google’s ${brightness == Brightness.light ? 'light' : 'dark'} scheme in '
        '${brightness == Brightness.light ? 'Print' : 'Darkroom'}', (tester) async {
      await openDialog(tester, brightness: brightness);

      final surface = tester.widget<Material>(
          find.descendant(of: find.byType(GoogleSignInButton), matching: find.byType(Material)));
      expect(surface.color, fill);
      expect((surface.shape! as OutlinedBorder).side, BorderSide(color: edge));
      expect(tester.renderObject<RenderParagraph>(find.text('Continue with Google')).text.style!.color, label);
      expect(surface.elevation, 0);
    });
  }

  testWidgets('Google’s button is one button named "Continue with Google"; the G adds nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    await openDialog(tester);

    expect(
      tester.getSemantics(find.byType(GoogleSignInButton)),
      isSemantics(
        label: 'Continue with Google',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
      ),
    );
    // The G is part of the button's look, not an image of its own.
    expect(find.semantics.byPredicate((node) => node.getSemanticsData().flagsCollection.isImage), findsNothing);
    semantics.dispose();
  });

  testWidgets('Google’s button: opened by a click, its focus shows no ring', (tester) async {
    await openDialog(tester);

    expect(Focus.of(tester.element(find.text('Continue with Google'))).hasPrimaryFocus, isTrue);
    expect(tester.widget<FocusRing>(find.descendant(of: find.byType(GoogleSignInButton), matching: find.byType(FocusRing))).visible,
        isFalse);
  });

  testWidgets('Google’s button: keyboard focus keeps Google’s edge and rings it past a gap', (tester) async {
    await tester.pumpWidget(testApp(auth: auth, home: _Opener(onResult: (_) {})));
    // Opened from the keyboard.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final google = find.byType(GoogleSignInButton);
    expect(Focus.of(tester.element(find.text('Continue with Google'))).hasPrimaryFocus, isTrue);
    final ring = tester.widget<FocusRing>(find.descendant(of: google, matching: find.byType(FocusRing)));
    expect(ring.visible, isTrue);
    expect(ring.color, isNull); // the system's focus color
    final surface = tester.widget<Material>(find.descendant(of: google, matching: find.byType(Material)));
    expect((surface.shape! as OutlinedBorder).side, const BorderSide(color: Color(0xFF747775)));
    // The ring paints outside the button, so the button mustn't clip it.
    expect(surface.clipBehavior, Clip.none);

    // Tab to Cancel and back.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.widget<FocusRing>(find.descendant(of: google, matching: find.byType(FocusRing))).visible, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(tester.widget<FocusRing>(find.descendant(of: google, matching: find.byType(FocusRing))).visible, isTrue);
  });

  testWidgets('Google’s button: hover lays Google’s 8% state layer over its fill', (tester) async {
    await openDialog(tester);
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: tester.getCenter(find.byType(GoogleSignInButton)));
    addTearDown(hover.removePointer);
    await tester.pumpAndSettle();

    final surface = tester.widget<Material>(
        find.descendant(of: find.byType(GoogleSignInButton), matching: find.byType(Material)));
    expect(surface.color, Color.alphaBlend(const Color(0xFF303030).withValues(alpha: 0.08), const Color(0xFFFFFFFF)));
    expect(tester.widget<FocusRing>(find.descendant(of: find.byType(GoogleSignInButton), matching: find.byType(FocusRing))).visible,
        isFalse);
  });

  testWidgets('on a narrow phone, the actions stack full width, primary first', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openDialog(tester);

    final primary = tester.getRect(find.byType(GoogleSignInButton));
    final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
    expect(primary.width, cancel.width);
    expect(primary.bottom, lessThan(cancel.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel closes with no user', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 0);
    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('in an in-app browser, explains how to open a real browser', (tester) async {
    await openDialog(tester, isEmbeddedBrowser: true);

    expect(find.text('Open in your browser to sign in'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    // Copying a link is the system's own primary button, not Google's.
    expect(find.byType(GoogleSignInButton), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Copy link'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('in an in-app browser, "Copy link" copies the page address', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await openDialog(tester, isEmbeddedBrowser: true);

    expect(find.byIcon(Icons.check), findsNothing);
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();

    expect(copied, Uri.base.toString());
    expect(find.text('Link copied'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('in an in-app browser, Close closes with no user', (tester) async {
    await openDialog(tester, isEmbeddedBrowser: true);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('signing in from the account control: "Sign in", about sessions and photos', (tester) async {
    await openDialog(tester);

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign in to book'), findsNothing);
    expect(find.text('Sign in with Google to see your sessions and download your photos.'), findsOneWidget);
  });

  testWidgets('signing in to book: "Sign in to book", about linking the booking', (tester) async {
    await openDialog(tester, toBook: true);

    expect(find.text('Sign in to book'), findsOneWidget);
    expect(
      find.text('Sign in with Google so we can link your booking, and later your photos, to your account.'),
      findsOneWidget,
    );
  });

  testWidgets('in an in-app browser, the help ends "to sign in."', (tester) async {
    await openDialog(tester, isEmbeddedBrowser: true);

    expect(find.textContaining(RegExp(r'in the app’s menu\) to sign in\.$')), findsOneWidget);
    expect(find.textContaining('to book your session'), findsNothing);
  });

  testWidgets('in an in-app browser while booking, the help ends "to book your session."', (tester) async {
    await openDialog(tester, isEmbeddedBrowser: true, toBook: true);

    expect(find.textContaining(RegExp(r'in the app’s menu\) to book your session\.$')), findsOneWidget);
    expect(find.text('Open in your browser to sign in'), findsOneWidget);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.windows, TargetPlatform.iOS]) {
    testWidgets('screen readers on ${platform.name} hear the title, not "Alert"', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final semantics = tester.ensureSemantics();
      await openDialog(tester, toBook: true);

      expect(find.bySemanticsLabel('Alert'), findsNothing);
      expect(
        find.semantics.byPredicate(
            (node) => node.label == 'Sign in to book' && node.getSemanticsData().flagsCollection.namesRoute),
        findsOne,
      );
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('casts the dialog shadow (${brightness.name})', (tester) async {
      await openDialog(tester, brightness: brightness);

      final colors = brightness == Brightness.dark ? BrookieColors.dark : BrookieColors.light;
      final panel = find.descendant(
        of: find.byType(Dialog),
        matching: find.byWidgetPredicate(
            (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).boxShadow != null),
      );
      final decoration = tester.widget<DecoratedBox>(panel).decoration as BoxDecoration;
      expect(decoration.boxShadow, colors.shadowDialog);
      expect(decoration.color, colors.surface);
      expect(decoration.borderRadius, BorderRadius.circular(BrookieRadius.md));
      // Material's own elevation shadow is off.
      final material = tester.widget<Material>(find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first);
      expect(material.elevation, 0);
      expect(tester.getSize(panel).width, lessThanOrEqualTo(440));
    });
  }

  for (final width in [320.0, 360.0]) {
    testWidgets('with large text on a ${width.toInt()}px phone, a sign-in error scrolls into view', (tester) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      auth.nextSignInError = const SignInException(
          'Your browser blocked the sign-in window. Allow pop-ups for this site, or open this page in Safari '
          'or Chrome, and try again.');
      await openDialog(tester);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final message = tester.getRect(find.byType(InlineMessage));
      final viewport = tester.getRect(find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)));
      // The whole message if it fits; otherwise it starts at the top.
      if (message.height <= viewport.height) {
        expect(message.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
        expect(message.top, greaterThanOrEqualTo(viewport.top - 0.5));
      } else {
        expect(message.top, moreOrLessEquals(viewport.top, epsilon: 0.5));
      }
    });
  }

  testWidgets('with a little larger text, a short error scrolls just far enough to show it', (tester) async {
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    auth.nextSignInError = const SignInException('Pop-ups are blocked.');
    await openDialog(tester);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    final message = tester.getRect(find.byType(InlineMessage));
    final viewport = tester.getRect(find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)));
    expect(message.height, lessThan(viewport.height));
    expect(message.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
    expect(message.top, greaterThanOrEqualTo(viewport.top - 0.5));
  });
}
