import 'package:brookie_babies/components/admin_gate.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';

/// One session, for admins: its details, who can download its photos, and
/// the photos themselves.
///
/// A first version: the session's page comes with the admin portal's second
/// phase.
class AdminSessionPage extends StatelessWidget {
  const AdminSessionPage({super.key, required this.sessionId});

  /// The `bookings` document id.
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrookieTopBar(title: 'Session', showAdminLink: false),
      body: AdminGate(
        child: SingleChildScrollView(
          child: ContentWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: BrookieSpace.s6),
              child: Text('This session’s photos will be managed here.',
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
        ),
      ),
    );
  }
}
