import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:flutter/material.dart';

/// "Sign in" when signed out; an avatar with an account menu ("My sessions",
/// "Sign out") when signed in.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, this.onPhoto = false});

  /// Whether the button sits on a photograph (the home page's hero) rather
  /// than on paper.
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final auth = AppServices.of(context).auth;
    return StreamBuilder<AppUser?>(
      stream: auth.authStateChanges,
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          return FilledButton.tonalIcon(
            onPressed: () => showSignInDialog(context),
            icon: const Icon(Icons.account_circle),
            label: const Text('Sign in'),
          );
        }
        return PopupMenuButton<void>(
          tooltip: 'Account',
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              enabled: false,
              child: Text(user.email ?? user.displayName ?? 'Signed in'),
            ),
            PopupMenuItem<void>(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (context) => const ProfilePage()),
              ),
              child: const Text('My sessions'),
            ),
            PopupMenuItem<void>(
              onTap: auth.signOut,
              child: const Text('Sign out'),
            ),
          ],
          child: CircleAvatar(child: Text(user.initial)),
        );
      },
    );
  }
}
