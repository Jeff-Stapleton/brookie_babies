import 'package:brookie_babies/components/admin_gate.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:brookie_babies/widgets/status_tag.dart';
import 'package:brookie_babies/widgets/top_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// "Admin": the studio's sessions, and the way to the home page photos
/// (route /admin). Admins only ([AdminGate]).
///
/// A first version: the sessions list comes with the admin portal's second
/// phase. The navigation and the notice below are final.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  /// Also linkable as https://brookie-babies.web.app/#/admin.
  static const routeName = '/admin';

  /// Opens the admin page over the home page, closing anything else that
  /// was open (the account menu's "Admin").
  static void open(BuildContext context) {
    _notice.value = null;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(settings: const RouteSettings(name: routeName), builder: (context) => const AdminPage()),
      (route) => route.isFirst,
    );
  }

  /// Goes back to the admin page and shows [message] there as a success
  /// notice: "Deleted the Harper family’s session."
  static void returnWithNotice(BuildContext context, String message) {
    // Home rather than an empty navigator, should the admin page not be
    // open below.
    Navigator.of(context).popUntil((route) => route.settings.name == routeName || route.isFirst);
    _notice.value = message;
  }

  /// The success notice to show, if any. The admin page shows it until it
  /// is [clearNotice]d, opened again, or closed.
  static ValueListenable<String?> get notice => _notice;

  static void clearNotice() => _notice.value = null;

  static final _notice = ValueNotifier<String?>(null);

  /// How many admin pages are open (briefly two, while one replaces another).
  static var _open = 0;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  @override
  void initState() {
    super.initState();
    AdminPage._open++;
  }

  @override
  void dispose() {
    // A notice is about this visit; the next one starts clean.
    if (--AdminPage._open == 0) AdminPage.clearNotice();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= BrookieBreakpoint.wide;
    return Scaffold(
      appBar: const BrookieTopBar(title: 'Admin', showAdminLink: false),
      body: AdminGate(
        child: SingleChildScrollView(
          child: ContentWidth(
            child: Padding(
              padding: EdgeInsets.only(
                top: wide ? BrookieSpace.s7 : BrookieSpace.s6,
                bottom: BrookieLayout.sectionGap(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder<String?>(
                    valueListenable: AdminPage.notice,
                    builder: (context, notice, child) => notice == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: BrookieSpace.s5),
                            child: InlineMessage(message: notice, tone: StatusTone.success),
                          ),
                  ),
                  Semantics(
                    header: true,
                    child: Text('Admin', style: Theme.of(context).textTheme.headlineLarge),
                  ),
                  const SizedBox(height: BrookieSpace.s3),
                  Text('Sessions and home page photos will be managed here.',
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
