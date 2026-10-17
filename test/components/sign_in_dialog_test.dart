import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Opens the dialog from a button and keeps what it completes with.
class _Opener extends StatelessWidget {
  const _Opener({required this.onResult});

  final void Function(AppUser?) onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElevatedButton(
        onPressed: () async => onResult(await showSignInDialog(context)),
        child: const Text('open'),
      ),
    );
  }
}

void main() {
  late FakeAuthService auth;
  AppUser? result;
  var completed = false;

  Future<void> openDialog(WidgetTester tester, {bool isEmbeddedBrowser = false}) async {
    await tester.pumpWidget(testApp(
      auth: auth,
      isEmbeddedBrowser: isEmbeddedBrowser,
      home: _Opener(onResult: (user) {
        result = user;
        completed = true;
      }),
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

  testWidgets('"Continue with Google" is the primary button, with no icon', (tester) async {
    await openDialog(tester);

    expect(find.widgetWithText(FilledButton, 'Continue with Google'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.byIcon(Icons.login), findsNothing);
  });

  testWidgets('on a narrow phone, the actions stack full width, primary first', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openDialog(tester);

    final primary = tester.getRect(find.widgetWithText(FilledButton, 'Continue with Google'));
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
}
