import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/account_avatar.dart';
import 'package:flutter/material.dart';

/// The account control at the right of a top bar: a "Sign in" chip when
/// signed out; when signed in, a butter avatar that opens the account menu
/// ("Your sessions", "Sign out").
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
        return user == null ? _SignInChip(onPhoto: onPhoto) : _AccountMenu(user: user);
      },
    );
  }
}

BorderSide _focusRing(BrookieColors c) =>
    BorderSide(color: c.focus, width: 2, strokeAlign: BorderSide.strokeAlignOutside);

class _SignInChip extends StatelessWidget {
  const _SignInChip({required this.onPhoto});

  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    return OutlinedButton.icon(
      onPressed: () => showSignInDialog(context),
      icon: const Icon(Icons.person_outline),
      label: const Text('Sign in'),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return c.surfaceSunk;
          // Paper with no edge reads over any part of a photograph.
          return onPhoto ? c.paper : c.surface;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return _focusRing(c);
          if (onPhoto) return BorderSide.none;
          if (states.contains(WidgetState.hovered)) return BorderSide(color: c.ink, width: 1.5);
          return BorderSide(color: c.lineStrong, width: 1.5);
        }),
        minimumSize: const WidgetStatePropertyAll(Size(0, BrookieSize.controlSm)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: BrookieSpace.s4)),
        // The chip is drawn 40px tall but answers taps across 48.
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final auth = AppServices.of(context).auth;
    const itemPadding = EdgeInsets.symmetric(horizontal: BrookieSpace.s4);
    // The menu takes its theme from here: rows highlight in surface-sunk, like
    // every other quiet control, instead of Material's grey overlay.
    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: c.surfaceSunk,
        focusColor: c.surfaceSunk,
        highlightColor: c.surfaceSunk,
      ),
      child: PopupMenuButton<void>(
        tooltip: 'Account',
        position: PopupMenuPosition.under,
        offset: const Offset(0, BrookieSpace.s2),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 224, maxWidth: 320),
        popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : const AnimationStyle(duration: kBrookieFadeDuration, reverseDuration: kBrookieFadeDuration),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          tapTargetSize: MaterialTapTargetSize.padded,
          // Like the butter button on a photograph: an on-butter edge on hover.
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) return _focusRing(c);
            if (states.contains(WidgetState.hovered)) return BorderSide(color: c.onButter, width: 1.5);
            return null;
          }),
        ),
        icon: AccountAvatar(user: user),
        itemBuilder: (context) => [
          _MenuHeader(user: user),
          const PopupMenuDivider(),
          PopupMenuItem<void>(
            padding: itemPadding,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (context) => const ProfilePage()),
            ),
            child: const Text('Your sessions'),
          ),
          PopupMenuItem<void>(
            padding: itemPadding,
            onTap: auth.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

/// Who is signed in, at the top of the account menu. Not a choice, so it
/// can't be focused or tapped.
class _MenuHeader extends PopupMenuEntry<void> {
  const _MenuHeader({required this.user});

  final AppUser user;

  @override
  double get height => 64;

  @override
  bool represents(void value) => false;

  @override
  State<_MenuHeader> createState() => _MenuHeaderState();
}

class _MenuHeaderState extends State<_MenuHeader> {
  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final name = widget.user.displayName?.trim() ?? '';
    final email = widget.user.email;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BrookieSpace.s4, BrookieSpace.s2, BrookieSpace.s4, BrookieSpace.s1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.isNotEmpty) Text(name, style: Theme.of(context).textTheme.titleSmall),
          if (email != null) Text(email, style: BrookieType.ui.copyWith(color: c.inkSoft)),
        ],
      ),
    );
  }
}
