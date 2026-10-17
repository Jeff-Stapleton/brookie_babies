import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks the visitor to sign in with Google. Completes with the signed-in user,
/// or null if they dismiss the dialog.
Future<AppUser?> showSignInDialog(BuildContext context) {
  _KeyboardInput.listen();
  return showDialog<AppUser>(
    context: context,
    animationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(duration: kBrookieFadeDuration, reverseDuration: kBrookieFadeDuration),
    builder: (context) => const SignInDialog(),
  );
}

class SignInDialog extends StatefulWidget {
  const SignInDialog({super.key});

  @override
  State<SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<SignInDialog> {
  int _attempt = 0;
  bool _linkCopied = false;
  String? _error;

  // The button stays enabled while the popup is open: Firebase only reports a
  // closed popup about 10 s later, and a new attempt cancels the old one.
  Future<void> _signIn() async {
    // Start the popup before anything else: browsers only allow it while
    // handling the tap.
    final signIn = AppServices.of(context).auth.signInWithGoogle();
    final attempt = ++_attempt;
    setState(() => _error = null);
    try {
      final user = await signIn;
      if (!mounted) return;
      if (user != null) Navigator.of(context).pop(user);
    } on SignInException catch (e) {
      // Ignore errors from an attempt the user has already retried.
      if (!mounted || attempt != _attempt) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _copyLink() async {
    try {
      await Clipboard.setData(ClipboardData(text: Uri.base.toString()));
    } on PlatformException {
      return; // In-app browsers often block the clipboard; the link is shown too.
    }
    if (mounted) setState(() => _linkCopied = true);
  }

  @override
  Widget build(BuildContext context) {
    if (AppServices.of(context).isEmbeddedBrowser) {
      return _BrookieDialog(
        title: 'Open in your browser to sign in',
        content: [
          // Typographic quotes: straight ones look like typewriter marks in
          // Newsreader.
          const Text(
              'Google sign-in doesn’t work inside apps like Instagram or '
              'Facebook. Open this page in Safari or Chrome (look for “Open '
              'in browser” in the app’s menu) to book your session.'),
          const SizedBox(height: BrookieSpace.s4),
          const _Link(),
        ],
        dismissLabel: 'Close',
        action: FilledButton.icon(
          autofocus: true,
          style: _primaryStyle(context),
          onPressed: _copyLink,
          icon: _linkCopied ? const Icon(Icons.check) : null,
          label: Text(_linkCopied ? 'Link copied' : 'Copy link'),
        ),
      );
    }

    final error = _error;
    return _BrookieDialog(
      title: 'Sign in to book',
      content: [
        const Text(
            'Sign in with Google so we can link your booking, and later '
            'your photos, to your account.'),
        if (error != null) ...[
          const SizedBox(height: BrookieSpace.s4),
          InlineMessage(message: error),
        ],
      ],
      dismissLabel: 'Cancel',
      action: FilledButton(
        autofocus: true,
        style: _primaryStyle(context),
        onPressed: _signIn,
        child: const Text('Continue with Google'),
      ),
    );
  }
}

/// The design system's dialog: a title, a sentence or two, a quiet dismissal
/// on the left and the primary action on the right.
class _BrookieDialog extends StatelessWidget {
  const _BrookieDialog({
    required this.title,
    required this.content,
    required this.dismissLabel,
    required this.action,
  });

  final String title;
  final List<Widget> content;
  final String dismissLabel;
  final Widget action;

  /// Below this window width "Cancel" and "Continue with Google" no longer
  /// fit side by side.
  static const _stackActionsBelow = 380.0;

  @override
  Widget build(BuildContext context) {
    final dismiss = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(dismissLabel),
    );
    return AlertDialog(
      // Scrolls on short screens rather than overflowing.
      scrollable: true,
      titlePadding: const EdgeInsets.fromLTRB(BrookieSpace.s5, BrookieSpace.s5, BrookieSpace.s5, 0),
      contentPadding: const EdgeInsets.fromLTRB(BrookieSpace.s5, BrookieSpace.s3, BrookieSpace.s5, BrookieSpace.s5),
      // If large text still crowds the row, the primary action goes on top.
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: BrookieSpace.s2,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      ),
      actions: MediaQuery.sizeOf(context).width < _stackActionsBelow
          // On a narrow phone, full-width buttons, the primary action first.
          ? [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [action, const SizedBox(height: BrookieSpace.s2), dismiss],
              ),
            ]
          : [dismiss, action],
    );
  }
}

/// This page's address, to paste into a real browser.
class _Link extends StatelessWidget {
  const _Link();

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceSunk,
        borderRadius: BorderRadius.circular(BrookieRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BrookieSpace.s3, vertical: BrookieSpace.s2),
        child: SelectableText(Uri.base.toString(), style: BrookieType.ui.copyWith(color: c.ink)),
      ),
    );
  }
}

/// The theme's primary button, ringed for focus only when the family is using
/// the keyboard. The dialog focuses its primary action as it opens, and after
/// a click that ring (and the hover fill that comes with it) would make the
/// button look already pressed.
ButtonStyle _primaryStyle(BuildContext context) {
  final c = BrookieColors.of(context);
  bool keyboardFocused(Set<WidgetState> states) =>
      states.contains(WidgetState.focused) && _KeyboardInput.lastWasKey;
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return c.surfaceSunk;
      if (states.contains(WidgetState.hovered) || keyboardFocused(states)) return c.inkSoft;
      return c.ink;
    }),
    // BorderSide.none rather than null, which would fall back to the theme's ring.
    side: WidgetStateProperty.resolveWith((states) => keyboardFocused(states)
        ? BorderSide(color: c.focus, width: 2, strokeAlign: BorderSide.strokeAlignOutside)
        : BorderSide.none),
  );
}

/// Whether the last input was a key press rather than a pointer, like the
/// browser's :focus-visible.
abstract final class _KeyboardInput {
  static bool _listening = false;
  static bool lastWasKey = false;

  static void listen() {
    if (_listening) return;
    _listening = true;
    // The first dialog may have been opened with Enter, which is still down.
    lastWasKey = HardwareKeyboard.instance.logicalKeysPressed.isNotEmpty;
    HardwareKeyboard.instance.addHandler((event) {
      lastWasKey = true;
      return false; // Only watching; the key still does what it does.
    });
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (event is PointerDownEvent) lastWasKey = false;
    });
  }
}
