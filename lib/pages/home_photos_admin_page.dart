import 'package:brookie_babies/components/admin_gate.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/material.dart';

/// "Home page photos", for admins: the public photo library, and which of
/// its photos the home page shows, in order.
///
/// A first version: choosing comes with the admin portal's second phase.
class HomePhotosAdminPage extends StatelessWidget {
  const HomePhotosAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrookieTopBar(title: 'Home page photos', showAdminLink: false),
      body: AdminGate(
        child: SingleChildScrollView(
          child: ContentWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: BrookieSpace.s6),
              child: Text('The home page photos will be chosen here.', style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
        ),
      ),
    );
  }
}
