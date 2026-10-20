import 'package:brookie_babies/components/admin_gate.dart';
import 'package:brookie_babies/models/booking.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';

/// Adds an ad hoc session (family, friends: no purchase), or edits [session].
///
/// A first version: the form comes with the admin portal's second phase.
class SessionFormPage extends StatelessWidget {
  const SessionFormPage({super.key, this.session});

  /// The ad hoc session to edit; null to add one.
  final Booking? session;

  @override
  Widget build(BuildContext context) {
    final adding = session == null;
    return Scaffold(
      appBar: BrookieTopBar(title: adding ? 'Add a session' : 'Edit session', showAdminLink: false),
      body: AdminGate(
        child: SingleChildScrollView(
          child: ContentWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: BrookieSpace.s6),
              child: Text('Sessions will be added and edited here.', style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
        ),
      ),
    );
  }
}
