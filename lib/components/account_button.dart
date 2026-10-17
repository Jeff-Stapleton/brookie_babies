import 'dart:math' as math;

import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/account_avatar.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The account control at the right of a top bar: a "Sign in" chip when
/// signed out; when signed in, a butter avatar that opens the account menu
/// ("Your sessions", "Sign out").
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, this.onPhoto = false, this.showSessionsLink = true});

  /// Whether the button sits on a photograph (the home page's hero) rather
  /// than on paper.
  final bool onPhoto;

  /// Whether the account menu links to "Your sessions". False on that page
  /// itself, so the menu doesn't open a second copy of it.
  final bool showSessionsLink;

  @override
  Widget build(BuildContext context) {
    final auth = AppServices.of(context).auth;
    return StreamBuilder<AppUser?>(
      stream: auth.authStateChanges,
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        return user == null
            ? _SignInChip(onPhoto: onPhoto)
            : _AccountMenu(user: user, onPhoto: onPhoto, showSessionsLink: showSessionsLink);
      },
    );
  }
}

/// How far a padded (48px) tap target reaches past a 40px control on each
/// side.
const _tapInset = (kMinInteractiveDimension - BrookieSize.controlSm) / 2;

/// The keyboard focus ring for a control on a photograph, as a button
/// layer: [FocusRing.onPhoto] around the button's painted shape, so it
/// shows on light and dark prints alike. The button must not clip
/// (`clipBehavior: Clip.none`), since the ring paints outside it.
ButtonLayerBuilder _photoFocusRing({bool circle = false}) {
  return (context, states, child) => FocusRing.onPhoto(
        visible: states.contains(WidgetState.focused),
        circle: circle,
        // Any radius past half the height draws a pill.
        borderRadius: circle ? null : BrookieSize.controlSm,
        child: child!,
      );
}

class _SignInChip extends StatelessWidget {
  const _SignInChip({required this.onPhoto});

  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    return OutlinedButton.icon(
      onPressed: () => showSignInDialog(context),
      clipBehavior: Clip.none,
      icon: const Icon(Icons.person_outline),
      label: const Text('Sign in'),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return c.surfaceSunk;
          // Paper with no edge reads over any part of a photograph.
          return onPhoto ? c.paper : c.surface;
        }),
        // BorderSide.none rather than null, which would fall back to the
        // theme's ring.
        side: WidgetStateProperty.resolveWith((states) {
          if (onPhoto) return BorderSide.none;
          if (states.contains(WidgetState.focused)) return brookieFocusSide(c.focus);
          if (states.contains(WidgetState.hovered)) return BorderSide(color: c.ink, width: 1.5);
          return BorderSide(color: c.lineStrong, width: 1.5);
        }),
        backgroundBuilder: onPhoto ? _photoFocusRing() : null,
        // The chip's label is 15px, a size down from a full button's.
        textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.titleSmall),
        minimumSize: const WidgetStatePropertyAll(Size(0, BrookieSize.controlSm)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: BrookieSpace.s4)),
        // The chip is drawn 40px tall but answers taps across 48.
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}

/// The signed-in avatar and the menu it opens.
///
/// The menu works like a menu button on the web: Enter, Space or the down
/// arrow opens it on its first item (the up arrow, on its last); the arrow
/// keys move between items and wrap around, Home and End jump to the first
/// and last, and Escape closes it and returns focus to the avatar. Opened
/// with a click, focus stays where it was.
class _AccountMenu extends StatefulWidget {
  const _AccountMenu({required this.user, required this.onPhoto, required this.showSessionsLink});

  final AppUser user;
  final bool onPhoto;
  final bool showSessionsLink;

  @override
  State<_AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends State<_AccountMenu> {
  final _controller = MenuController();
  final _avatarFocus = FocusNode(debugLabel: 'Account');
  final _sessionsFocus = FocusNode(debugLabel: 'Your sessions');
  final _signOutFocus = FocusNode(debugLabel: 'Sign out');

  List<FocusNode> get _items => [if (widget.showSessionsLink) _sessionsFocus, _signOutFocus];

  @override
  void dispose() {
    _avatarFocus.dispose();
    _sessionsFocus.dispose();
    _signOutFocus.dispose();
    super.dispose();
  }

  /// Opens the menu (if it isn't open) and focuses its first or last item
  /// once the items are built.
  void _openOn({required bool last}) {
    if (!_controller.isOpen) _controller.open();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isOpen) return;
      final items = _items;
      (last ? items.last : items.first).requestFocus();
    });
  }

  void _toggle() {
    if (_controller.isOpen) {
      _controller.close();
    } else if (_avatarFocus.hasPrimaryFocus) {
      // From the keyboard or a screen reader: into the menu.
      _openOn(last: false);
    } else {
      _controller.open();
    }
  }

  /// Moves focus [by] items, wrapping around at either end.
  void _move(int by) {
    final items = _items;
    final current = items.indexWhere((node) => node.hasPrimaryFocus);
    final next = current < 0 ? (by > 0 ? 0 : items.length - 1) : (current + by) % items.length;
    items[next].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final auth = AppServices.of(context).auth;
    final direction = Directionality.of(context);
    final gutter = BrookieLayout.gutter(context);
    final maxWidth = math.min(320.0, MediaQuery.sizeOf(context).width - 2 * gutter);

    final itemStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ? c.surfaceSunk : Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(c.ink),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      // A real ring, like every other control, rather than a faint band.
      side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? brookieFocusSide(c.focus) : BorderSide.none),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrookieRadius.sm))),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: BrookieSpace.s2)),
      minimumSize: const WidgetStatePropertyAll(Size(0, kMinInteractiveDimension)),
      textStyle: WidgetStatePropertyAll(BrookieType.ui),
      animationDuration: kBrookieStateDuration,
    );

    final menu = Directionality(
      textDirection: direction,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.home): () => _items.first.requestFocus(),
          const SingleActivator(LogicalKeyboardKey.end): () => _items.last.requestFocus(),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuHeader(user: widget.user),
            const Divider(height: BrookieSpace.s4),
            // The items sit in from the menu's edge so their focus ring
            // (2px out, past a 2px gap) isn't clipped.
            Padding(
              padding: const EdgeInsets.fromLTRB(BrookieSpace.s2, BrookieSpace.s1, BrookieSpace.s2, BrookieSpace.s2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.showSessionsLink) ...[
                    MenuItemButton(
                      focusNode: _sessionsFocus,
                      // Hovering highlights a row; only the keyboard moves the ring.
                      requestFocusOnHover: false,
                      style: itemStyle,
                      // This state's context: the menu's own is gone by the
                      // time a chosen item runs.
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (context) => const ProfilePage()),
                      ),
                      child: const Text('Your sessions'),
                    ),
                    const SizedBox(height: BrookieSpace.s1),
                  ],
                  MenuItemButton(
                    focusNode: _signOutFocus,
                    requestFocusOnHover: false,
                    style: itemStyle,
                    onPressed: auth.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // The avatar sits at the window's right edge, so the menu hangs from its
    // right edge (as the old popup menu did). MenuAnchor only lines a menu
    // up by its far edge in the opposite reading direction, so it is laid
    // out in that direction and the menu and the avatar are set back.
    final flipped = direction == TextDirection.ltr ? TextDirection.rtl : TextDirection.ltr;
    return Directionality(
      textDirection: flipped,
      child: MenuAnchor(
        controller: _controller,
        childFocusNode: _avatarFocus,
        // A click outside only closes the menu, as the popup menu's barrier did.
        consumeOutsideTap: true,
        crossAxisUnconstrained: false,
        // Lined up with the 40px avatar, not its 48px tap target, s2 below it.
        alignmentOffset: const Offset(_tapInset, BrookieSpace.s2 - _tapInset),
        style: MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          backgroundColor: WidgetStatePropertyAll(c.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          // Edges come from hairlines; only photographs and dialogs cast shadows.
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: c.line)),
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrookieRadius.md))),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          visualDensity: VisualDensity.standard,
          minimumSize: WidgetStatePropertyAll(Size(math.min(224, maxWidth), 0)),
          maximumSize: WidgetStatePropertyAll(Size(maxWidth, double.infinity)),
        ),
        menuChildren: [menu],
        builder: (context, controller, child) => Directionality(
          textDirection: direction,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () => _openOn(last: false),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () => _openOn(last: true),
            },
            // One node: "Account", a button, expanded or collapsed.
            child: MergeSemantics(
              child: Semantics(
                expanded: controller.isOpen,
                child: IconButton(
                  focusNode: _avatarFocus,
                  tooltip: 'Account',
                  onPressed: _toggle,
                  style: ButtonStyle(
                    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    // Like the butter button on a photograph: an on-butter
                    // edge on hover. BorderSide.none rather than null, which
                    // would fall back to the theme's ring.
                    side: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return widget.onPhoto ? BorderSide.none : brookieFocusSide(c.focus);
                      }
                      if (states.contains(WidgetState.hovered)) return BorderSide(color: c.onButter, width: 1.5);
                      return BorderSide.none;
                    }),
                    backgroundBuilder: widget.onPhoto ? _photoFocusRing(circle: true) : null,
                  ),
                  icon: AccountAvatar(user: widget.user),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Who is signed in, at the top of the account menu. Not a choice, so it
/// can't be focused or tapped.
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final name = user.displayName?.trim() ?? '';
    final email = user.email;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BrookieSpace.s4, BrookieSpace.s4, BrookieSpace.s4, BrookieSpace.s1),
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
