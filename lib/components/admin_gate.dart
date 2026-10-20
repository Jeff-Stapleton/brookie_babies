import 'dart:developer';

import 'package:brookie_babies/components/account_button.dart';
import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';

/// Shows [child] (an admin page's body) only to admins: anyone else is
/// asked to sign in with the studio's account.
///
/// The check is for the page's sake: firestore.rules and storage.rules
/// refuse non-admins whatever the app shows. The token the app has
/// answers, so moving between admin pages needs no network; only a "no" is
/// checked again with a fresh token, so someone just made an admin only
/// needs to open the page again.
class AdminGate extends StatelessWidget {
  const AdminGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = AppServices.of(context).auth;
    return StreamBuilder<AppUser?>(
      stream: auth.authStateChanges,
      // Firebase restores the session before the app starts, so there is
      // no "still signing in" state to wait through.
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return const _SignedOut();
        // Keyed by uid, so a different account is checked afresh.
        return _AdminCheck(key: ValueKey(user.uid), user: user, child: child);
      },
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    return _GateFrame(
      children: [
        Text(
          'Sign in with the studio’s Google account to manage sessions and photos.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: BrookieSpace.s5),
        FilledButton(
          onPressed: () => showSignInDialog(context),
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}

class _AdminCheck extends StatefulWidget {
  const _AdminCheck({super.key, required this.user, required this.child});

  final AppUser user;
  final Widget child;

  @override
  State<_AdminCheck> createState() => _AdminCheckState();
}

class _AdminCheckState extends State<_AdminCheck> {
  late final Future<bool> _isAdmin;

  @override
  void initState() {
    super.initState();
    _isAdmin = _check(AppServices.of(context).auth);
  }

  // The first check after a page load fetches a new token anyway; after
  // that, a fresh one only for a "no", which it might change.
  static Future<bool> _check(AuthService auth) async => await auth.isAdmin() || await auth.isAdmin(refresh: true);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdmin,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          log('Checking admin access failed: ${snapshot.error}');
          return const _GateFrame(
            children: [InlineMessage(message: 'We couldn’t check your access. Refresh the page to try again.')],
          );
        }
        final isAdmin = snapshot.data;
        if (isAdmin == null) {
          return const _GateFrame(
            children: [
              Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          );
        }
        if (isAdmin) return widget.child;
        return _NotAdmin(user: widget.user);
      },
    );
  }
}

class _NotAdmin extends StatelessWidget {
  const _NotAdmin({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final email = user.email;
    return _GateFrame(
      children: [
        Text(
          email == null
              ? 'This account isn’t an admin. Sign out and sign in with the studio’s Google account.'
              : 'This account ($email) isn’t an admin. Sign out and sign in with the studio’s Google account.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: BrookieSpace.s5),
        OutlinedButton(
          onPressed: () => signOutWithWarning(context),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

/// The gate's messages, where the page's content would start: in the
/// content column, s7 below the top bar from 900px wide (s6 on smaller
/// screens), held to the reading width.
class _GateFrame extends StatelessWidget {
  const _GateFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= BrookieBreakpoint.wide;
    return SingleChildScrollView(
      child: ContentWidth(
        child: Padding(
          padding: EdgeInsets.only(
            top: wide ? BrookieSpace.s7 : BrookieSpace.s6,
            bottom: BrookieLayout.sectionGap(context),
          ),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
        ),
      ),
    );
  }
}
