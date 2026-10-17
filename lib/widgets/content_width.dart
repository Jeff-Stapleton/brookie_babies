import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// Centers the page's content column, at most [maxWidth] wide, with the page
/// gutter on both sides. [child] fills the column, so content narrower than it
/// stays left-aligned with the rest of the page.
///
/// Use [BrookieSize.readingWidth] for blocks of body or lede text.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = BrookieSize.contentWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final gutter = BrookieLayout.gutter(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + 2 * gutter),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}
