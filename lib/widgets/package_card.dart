import 'package:brookie_babies/models/session_package.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// One session package: its name, price, what it includes and the button that
/// chooses it.
///
/// The [selected] card turns butter with an ink ring, says "Selected", and its
/// button changes from "Choose Premium" to "Continue with Premium". Given a
/// bounded height (cards side by side at equal height), the button stays at
/// the bottom.
class PackageCard extends StatefulWidget {
  const PackageCard({super.key, required this.package, required this.onChoose, this.selected = false});

  final SessionPackage package;
  final VoidCallback onChoose;
  final bool selected;

  /// Horizontal padding of the card and of its button.
  static const padding = BrookieSpace.s5;
  static const buttonPadding = BrookieSpace.s4;

  /// The button's padding: [buttonPadding] at the sides, and room above and
  /// below for a label that wraps at large text sizes.
  static const _buttonInsets = EdgeInsets.symmetric(horizontal: buttonPadding, vertical: BrookieSpace.s2);

  /// The button's label for [package].
  static String buttonLabel(SessionPackage package, {required bool selected}) =>
      selected ? 'Continue with ${package.name}' : 'Choose ${package.name}';

  @override
  State<PackageCard> createState() => _PackageCardState();
}

class _PackageCardState extends State<PackageCard> {
  // One focus node for whichever button the card shows, so a keyboard user
  // who chose this card comes back to it, now "Continue with …".
  final _buttonFocus = FocusNode(debugLabel: 'PackageCard button');

  @override
  void dispose() {
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final package = widget.package;
    final selected = widget.selected;
    final foreground = selected ? c.onButter : c.ink;
    // Butter needs a darker hairline than line to show at all.
    final hairline = selected ? c.onButter.withValues(alpha: 0.18) : c.line;
    final label = Text(PackageCard.buttonLabel(package, selected: selected), textAlign: TextAlign.center);

    return Semantics(
      container: true,
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? c.butter : c.surface,
          borderRadius: BorderRadius.circular(BrookieRadius.md),
          // Butter is barely visible on paper, so the selection is carried by
          // an ink ring around the card.
          border: selected
              ? Border.all(color: c.ink, width: 1.5, strokeAlign: BorderSide.strokeAlignOutside)
              : Border.all(color: c.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(PackageCard.padding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // "Selected" drops below the name when both don't fit on
                  // one line, rather than squeezing the name.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: BrookieSpace.s3,
                    runSpacing: BrookieSpace.s1,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(package.name, style: BrookieType.title.copyWith(color: foreground)),
                      ),
                      if (selected) _SelectedMark(color: c.onButter),
                    ],
                  ),
                  const SizedBox(height: BrookieSpace.s4),
                  Text(package.priceLabel, style: BrookieType.price.copyWith(color: foreground)),
                  const SizedBox(height: BrookieSpace.s4),
                  for (final inclusion in package.inclusions)
                    DecoratedBox(
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: hairline))),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: BrookieSpace.s2),
                        child: Text(inclusion, style: BrookieType.ui.copyWith(color: foreground)),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: BrookieSpace.s4),
                child: selected
                    ? FilledButton(
                        onPressed: widget.onChoose,
                        focusNode: _buttonFocus,
                        style: _onButterStyle(c),
                        child: label,
                      )
                    : OutlinedButton(
                        onPressed: widget.onChoose,
                        focusNode: _buttonFocus,
                        style: const ButtonStyle(padding: WidgetStatePropertyAll(PackageCard._buttonInsets)),
                        child: label,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The action inside a selected card: on-butter fill with butter text.
  static ButtonStyle _onButterStyle(BrookieColors c) => ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(c.onButter),
        foregroundColor: WidgetStatePropertyAll(c.butter),
        padding: const WidgetStatePropertyAll(PackageCard._buttonInsets),
        // The focus ring in on-butter, with the card's butter showing in the
        // gap: the theme's ink ring is too faint on butter in Darkroom. None
        // rather than null otherwise, or the theme's ring comes back.
        side: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.focused) ? brookieFocusSide(c.onButter) : BorderSide.none),
      );
}

class _SelectedMark extends StatelessWidget {
  const _SelectedMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // Grows with the word beside it at large text sizes.
        Icon(Icons.check, size: 16, color: color, applyTextScaling: true),
        const SizedBox(width: BrookieSpace.s1),
        Text('Selected', style: BrookieType.small.copyWith(color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
