import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:flutter/material.dart';

/// An admin page's scrolling body, framed like "Your sessions" (and
/// AdminGate's messages), so the headline sits in the same place on every
/// page: in the content column, s7 below the top bar from 900px wide (s6 on
/// smaller screens), with the page's own column of at most [maxWidth]
/// left-aligned in it.
class AdminFrame extends StatelessWidget {
  const AdminFrame({super.key, this.controller, this.maxWidth = listWidth, required this.child});

  final ScrollController? controller;
  final double maxWidth;
  final Widget child;

  /// A list of sessions reads best as one column, narrower than the page:
  /// the width "Your sessions" lists them in.
  static const listWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= BrookieBreakpoint.wide;
    return SingleChildScrollView(
      controller: controller,
      child: ContentWidth(
        child: Padding(
          padding: EdgeInsets.only(
            top: wide ? BrookieSpace.s7 : BrookieSpace.s6,
            bottom: BrookieLayout.sectionGap(context),
          ),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A page or section title, marked as a heading for screen readers.
class AdminHeading extends StatelessWidget {
  const AdminHeading(this.text, {super.key, this.page = false});

  final String text;

  /// The page's headline rather than a section's title.
  final bool page;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      // Who a session is for can be a long email.
      child: Text(
        breakableEmail(text),
        semanticsLabel: text,
        style: page ? textTheme.headlineLarge : textTheme.titleLarge,
      ),
    );
  }
}

/// [text] for display, and if it's an email, with a line break allowed
/// after each "@" and ".", so a long one ("a.long.name@example.com") wraps
/// there rather than mid-word. Zero-width spaces: show it with [text] as
/// the semantics label, and never where it can be copied.
String breakableEmail(String text) =>
    text.contains('@') ? text.replaceAllMapped(RegExp('[@.](?=.)'), (match) => '${match[0]}\u200B') : text;
