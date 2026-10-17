import 'package:brookie_babies/models/app_user.dart';
import 'package:brookie_babies/services/app_services.dart';
import 'package:brookie_babies/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks the visitor to sign in with Google. Completes with the signed-in user,
/// or null if they dismiss the dialog.
Future<AppUser?> showSignInDialog(BuildContext context) {
  return showDialog<AppUser>(
    context: context,
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
      return AlertDialog(
        title: const Text('Open in your browser to sign in'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                "Google sign-in doesn't work inside apps like Instagram or "
                'Facebook. Open this page in Safari or Chrome (look for "Open '
                'in browser" in the app\'s menu) to book your session.'),
            const SizedBox(height: 16),
            SelectableText(Uri.base.toString()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: _copyLink,
            icon: Icon(_linkCopied ? Icons.check : Icons.copy),
            label: Text(_linkCopied ? 'Link copied' : 'Copy link'),
          ),
        ],
      );
    }

    final error = _error;
    return AlertDialog(
      title: const Text('Sign in to book'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Sign in with Google so we can link your booking, and later '
              'your photos, to your account.'),
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _signIn,
          icon: const Icon(Icons.login),
          label: const Text('Continue with Google'),
        ),
      ],
    );
  }
}
