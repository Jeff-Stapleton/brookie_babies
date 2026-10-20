import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/keyboard_input.dart';
import 'package:brookie_babies/widgets/brookie_dialog.dart';
import 'package:brookie_babies/widgets/google_sign_in_button.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks the visitor to sign in with Google. Completes with the signed-in user,
/// or null if they dismiss the dialog.
Future<AppUser?> showSignInDialog(BuildContext context, {bool toBook = false}) {
  // So the G is there as the dialog fades in.
  if (!AppServices.of(context).isEmbeddedBrowser) precacheImage(GoogleSignInButton.logo, context);
  return showBrookieDialog<AppUser>(context, builder: (context) => SignInDialog(toBook: toBook));
}

class SignInDialog extends StatefulWidget {
  const SignInDialog({super.key, this.toBook = false});

  /// Whether the family is signing in to book a session (from the booking
  /// page) rather than to see their sessions and photos.
  final bool toBook;

  @override
  State<SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<SignInDialog> {
  int _attempt = 0;
  bool _linkCopied = false;
  String? _error;

  /// The error message, so it can be scrolled into view: with large text on
  /// a small phone the dialog scrolls, and the message lands below the fold.
  final _errorKey = GlobalKey();

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
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealError());
    }
  }

  void _revealError() {
    final message = _errorKey.currentContext;
    if (message == null || !mounted) return;
    final height = message.size?.height ?? 0;
    final viewport = Scrollable.maybeOf(message)?.position.viewportDimension ?? double.infinity;
    Scrollable.ensureVisible(
      message,
      // Scroll just far enough to show all of it; if it's taller than the
      // dialog, show its start.
      alignmentPolicy: height <= viewport
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.explicit,
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : kBrookieFadeDuration,
      curve: Curves.easeOut,
    );
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
    final toBook = widget.toBook;
    if (AppServices.of(context).isEmbeddedBrowser) {
      return BrookieDialog(
        title: 'Open in your browser to sign in',
        content: [
          // Typographic quotes: straight ones look like typewriter marks in
          // Newsreader.
          Text('Google sign-in doesn’t work inside apps like Instagram or '
              'Facebook. Open this page in Safari or Chrome (look for “Open '
              'in browser” in the app’s menu) ${toBook ? 'to book your session' : 'to sign in'}.'),
          const SizedBox(height: BrookieSpace.s4),
          const _Link(),
        ],
        dismissLabel: 'Close',
        // Rebuilt when the family switches between keyboard and mouse, so
        // the ring follows, like the browser's :focus-visible.
        action: ValueListenableBuilder<bool>(
          valueListenable: KeyboardInput.changes,
          builder: (context, lastWasKey, child) => FilledButton.icon(
            autofocus: true,
            style: brookieDialogPrimaryStyle(context),
            onPressed: _copyLink,
            icon: _linkCopied ? const Icon(Icons.check) : null,
            label: Text(_linkCopied ? 'Link copied' : 'Copy link'),
          ),
        ),
      );
    }

    final error = _error;
    return BrookieDialog(
      title: toBook ? 'Sign in to book' : 'Sign in',
      content: [
        Text(toBook
            ? 'Sign in with Google so we can link your booking, and later '
                'your photos, to your account.'
            : 'Sign in with Google to see your sessions and download your photos.'),
        if (error != null) ...[
          const SizedBox(height: BrookieSpace.s4),
          InlineMessage(key: _errorKey, message: error),
        ],
      ],
      dismissLabel: 'Cancel',
      // Google's own button, as the Dialog spec asks.
      action: GoogleSignInButton(autofocus: true, onPressed: _signIn),
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
