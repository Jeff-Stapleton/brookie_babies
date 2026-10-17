import 'package:brookie_babies/models/session_package.dart';
import 'package:brookie_babies/pages/scheduling_page.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/content_width.dart';
import 'package:brookie_babies/widgets/package_card.dart';
import 'package:flutter/material.dart';

/// "Choose your package": a short introduction and a card per package.
///
/// Choosing a package opens the scheduling page for it. The choice is
/// remembered, so coming back shows that card selected, ready to continue.
class Packages extends StatefulWidget {
  const Packages({super.key});

  @override
  State<Packages> createState() => _PackagesState();
}

class _PackagesState extends State<Packages> {
  String? _chosen;

  void _choose(SessionPackage package) {
    setState(() => _chosen = package.name);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => SchedulingPage(packageName: package.name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Choose your package', style: Theme.of(context).textTheme.headlineLarge),
          ),
          // A sentence under a headline: s3 below it, in body and ink, as on
          // every page.
          const SizedBox(height: BrookieSpace.s3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: BrookieSize.readingWidth),
            child: Text(
              'After your session, your edited photos arrive in your account, ready to download.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: BrookieSpace.s6),
          _PackageCards(chosen: _chosen, onChoose: _choose),
        ],
      ),
    );
  }
}

/// The cards side by side at equal height from [BrookieBreakpoint.packages],
/// stacked below that.
class _PackageCards extends StatelessWidget {
  const _PackageCards({required this.chosen, required this.onChoose});

  final String? chosen;
  final ValueChanged<SessionPackage> onChoose;

  static const _gap = BrookieSpace.s4;

  /// The narrowest card whose longest button label still fits on one line.
  double _minCardWidth(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final package in SessionPackage.all) {
      for (final selected in [false, true]) {
        final painter = TextPainter(
          text: TextSpan(text: PackageCard.buttonLabel(package, selected: selected), style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        if (painter.width > widest) widest = painter.width;
        painter.dispose();
      }
    }
    // Both paddings on each side, plus the card's 1px edges.
    return widest + 2 * (PackageCard.padding + PackageCard.buttonPadding + 1);
  }

  @override
  Widget build(BuildContext context) {
    final packages = SessionPackage.all;
    final wideWindow = MediaQuery.sizeOf(context).width >= BrookieBreakpoint.packages;

    Widget card(SessionPackage package) => PackageCard(
          package: package,
          selected: package.name == chosen,
          onChoose: () => onChoose(package),
        );

    return LayoutBuilder(builder: (context, constraints) {
      final cardWidth = (constraints.maxWidth - _gap * (packages.length - 1)) / packages.length;
      // Just above the breakpoint (or with large text) three cards can be too
      // narrow for "Continue with Ultimate"; stack them rather than wrap it.
      final sideBySide = wideWindow && cardWidth >= _minCardWidth(context);
      if (!sideBySide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final package in packages) ...[
              if (package != packages.first) const SizedBox(height: _gap),
              card(package),
            ],
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final package in packages) ...[
              if (package != packages.first) const SizedBox(width: _gap),
              Expanded(child: card(package)),
            ],
          ],
        ),
      );
    });
  }
}
