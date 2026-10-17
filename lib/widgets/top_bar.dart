import 'package:brookie_babies/components/account_button.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// The bar across the top of every page after the home page: back, the
/// page's short name, and the account control. On paper with a hairline
/// underneath (the AppBar theme), never a shadow.
class BrookieTopBar extends StatelessWidget implements PreferredSizeWidget {
  const BrookieTopBar({super.key, required this.title, this.showSessionsLink = true});

  /// Two to four words, sentence case.
  final String title;

  /// See [AccountButton.showSessionsLink].
  final bool showSessionsLink;

  static const _height = 64.0;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    // Opened straight from a link there is nothing to go back to.
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return AppBar(
      toolbarHeight: _height,
      automaticallyImplyLeading: false,
      // The back button sits on the page gutter, the title s2 after it.
      leadingWidth: canPop ? BrookieSpace.s4 + BrookieSize.controlSm : null,
      leading: canPop
          ? Padding(
              padding: const EdgeInsets.only(left: BrookieSpace.s4),
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.maybePop(context),
              ),
            )
          : null,
      titleSpacing: canPop ? BrookieSpace.s2 : BrookieSpace.s4,
      title: Text(title),
      actions: [
        AccountButton(showSessionsLink: showSessionsLink),
        const SizedBox(width: BrookieSpace.s4),
      ],
    );
  }
}
