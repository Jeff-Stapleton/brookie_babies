import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// Centers [child] in the page's content column: at most [maxWidth] wide, with
/// the page gutter on both sides.
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
          child: child,
        ),
      ),
    );
  }
}
