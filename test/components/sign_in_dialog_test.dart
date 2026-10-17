import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:flutter/material.dart';
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

    expect(find.text('Pop-ups are blocked.'), findsOneWidget);
    expect(find.byType(SignInDialog), findsOneWidget);
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
  });
}
