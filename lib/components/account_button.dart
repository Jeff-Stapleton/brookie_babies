import 'dart:math' as math;

import 'package:brookie_babies/components/sign_in_dialog.dart';
import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/pages/profile_page.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/keyboard_input.dart';
import 'package:brookie_babies/widgets/account_avatar.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The account control at the right of a top bar: a "Sign in" chip when
/// signed out; when signed in, a butter avatar that opens the account menu
/// ("Your sessions", "Sign out").
///
/// Its focus rings show only for keyboard focus ([KeyboardInput]): the
/// avatar takes focus when its menu opens, and the chip when the sign-in
/// dialog closes, and after a click a ring would look like keyboard focus.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, this.onPhoto = false, this.showSessionsLink = true});

  /// Whether the button sits on a photograph (the home page's hero) rather
  /// than on paper.
  final bool onPhoto;

  /// Whether this control is anywhere but "Your sessions" itself. False on
  /// that page: the account menu leaves out the link to it (it would open a
  /// second copy), and signed out the control shows nothing, since the page
  /// has its own "Sign in" button.
  final bool showSessionsLink;

  @override
  Widget build(BuildContext context) {
    KeyboardInput.listen();
    final auth = AppServices.of(context).auth;
    return StreamBuilder<AppUser?>(
      stream: auth.authStateChanges,
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user != null) return _AccountMenu(user: user, onPhoto: onPhoto, showSessionsLink: showSessionsLink);
        // On "Your sessions" the page's own "Sign in" is the one way in.
        return showSessionsLink ? _SignInChip(onPhoto: onPhoto) : const SizedBox.shrink();
      },
    );
  }
}

/// How far a padded (48px) tap target reaches past a 40px control on each
/// side.
const _tapInset = (kMinInteractiveDimension - BrookieSize.controlSm) / 2;

/// Whether [states] hold focus that came from the keyboard.
bool _keyboardFocused(Set<WidgetState> states) => states.contains(WidgetState.focused) && KeyboardInput.lastWasKey;

/// The keyboard focus ring as a button layer, painted outside the button's
/// own edge so the 2px gap shows between them: [FocusRing.onPhoto] on a
/// photograph (it shows on light and dark prints alike), [FocusRing] on
/// paper (for a pill). The button must not clip (`clipBehavior:
/// Clip.none`), since the ring paints outside it.
ButtonLayerBuilder _focusRingLayer({required bool onPhoto, bool circle = false}) {
  assert(onPhoto || !circle, 'On paper a round button rings itself with brookieFocusSide.');
  return (context, states, child) {
    final visible = _keyboardFocused(states);
    // Any radius past half the height draws a pill.
    const pill = BrookieSize.controlSm;
    return onPhoto
        ? FocusRing.onPhoto(visible: visible, circle: circle, borderRadius: circle ? null : pill, child: child!)
        : FocusRing(visible: visible, borderRadius: pill, child: child!);
  };
}

class _SignInChip extends StatelessWidget {
  const _SignInChip({required this.onPhoto});

  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    // On a photograph the chip keeps Print's paper and ink in both themes,
    // as the butter button on the same photograph does: Darkroom's paper
    // would all but vanish into a dark print.
    final c = onPhoto ? BrookieColors.light : BrookieColors.of(context);
    // Rebuilt when the family switches between keyboard and mouse, so the
    // ring follows, like the browser's :focus-visible.
    return ValueListenableBuilder<bool>(
      valueListenable: KeyboardInput.changes,
      builder: (context, lastWasKey, child) => OutlinedButton.icon(
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
          foregroundColor: WidgetStatePropertyAll(c.ink),
          iconColor: WidgetStatePropertyAll(c.ink),
          // Focused, the chip keeps its own edge and the ring is drawn
          // outside it, past a 2px gap, so focus looks unlike hover.
          // BorderSide.none rather than null, which would fall back to the
          // theme's.
          side: WidgetStateProperty.resolveWith((states) {
            if (onPhoto) return BorderSide.none;
            if (states.contains(WidgetState.hovered)) return BorderSide(color: c.ink, width: 1.5);
            return BorderSide(color: c.lineStrong, width: 1.5);
          }),
          backgroundBuilder: _focusRingLayer(onPhoto: onPhoto),
          // The chip's label is 15px, a size down from a full button's.
          textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.titleSmall),
          minimumSize: const WidgetStatePropertyAll(Size(0, BrookieSize.controlSm)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: BrookieSpace.s4)),
          // The chip is drawn 40px tall but answers taps across 48.
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
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
/// with a click or a tap, focus doesn't move into the menu, and the avatar
/// (which MenuAnchor focuses) shows no ring.
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
    } else if (_avatarFocus.hasPrimaryFocus && KeyboardInput.lastWasKey) {
      // Enter or Space on the focused avatar: into the menu.
      _openOn(last: false);
    } else {
      // A click or a tap, even on an avatar that already has focus (opening
      // the menu focuses it): focus stays out of the menu.
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
          // No shadow (only photographs and dialogs cast one), so the edge
          // is what sets the menu apart from the page under it: an edge that
          // carries meaning, so line-strong.
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: c.lineStrong)),
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
                // Rebuilt when the family switches between keyboard and
                // mouse, so the ring follows, like the browser's
                // :focus-visible.
                child: ValueListenableBuilder<bool>(
                  valueListenable: KeyboardInput.changes,
                  builder: (context, lastWasKey, child) => IconButton(
                    focusNode: _avatarFocus,
                    tooltip: 'Account',
                    onPressed: _toggle,
                    style: ButtonStyle(
                      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                      tapTargetSize: MaterialTapTargetSize.padded,
                      // Like the butter button on a photograph: an on-butter
                      // edge on hover. BorderSide.none rather than null,
                      // which would fall back to the theme's ring.
                      side: WidgetStateProperty.resolveWith((states) {
                        if (_keyboardFocused(states)) {
                          return widget.onPhoto ? BorderSide.none : brookieFocusSide(c.focus);
                        }
                        if (states.contains(WidgetState.hovered)) return BorderSide(color: c.onButter, width: 1.5);
                        return BorderSide.none;
                      }),
                      backgroundBuilder: widget.onPhoto ? _focusRingLayer(onPhoto: true, circle: true) : null,
                    ),
                    icon: AccountAvatar(user: widget.user),
                  ),
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
