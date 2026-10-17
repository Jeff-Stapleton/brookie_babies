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
class PackageCard extends StatelessWidget {
  const PackageCard({super.key, required this.package, required this.onChoose, this.selected = false});

  final SessionPackage package;
  final VoidCallback onChoose;
  final bool selected;

  /// Horizontal padding of the card and of its button.
  static const padding = BrookieSpace.s5;
  static const buttonPadding = BrookieSpace.s4;

  /// The button's label for [package].
  static String buttonLabel(SessionPackage package, {required bool selected}) =>
      selected ? 'Continue with ${package.name}' : 'Choose ${package.name}';

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final foreground = selected ? c.onButter : c.ink;
    // Butter needs a darker hairline than line to show at all.
    final hairline = selected ? c.onButter.withValues(alpha: 0.18) : c.line;
    final label = buttonLabel(package, selected: selected);

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
          padding: const EdgeInsets.all(padding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(package.name, style: BrookieType.title.copyWith(color: foreground)),
                        ),
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
                    ? FilledButton(onPressed: onChoose, style: _onButterStyle(c), child: Text(label))
                    : OutlinedButton(
                        onPressed: onChoose,
                        style: const ButtonStyle(
                          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: buttonPadding)),
                        ),
                        child: Text(label),
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
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: buttonPadding)),
        // The theme's ink focus ring is too faint on butter in Darkroom.
        side: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused)
            ? BorderSide(color: c.onButter, width: 2, strokeAlign: BorderSide.strokeAlignOutside)
            : null),
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
        Icon(Icons.check, size: 16, color: color),
        const SizedBox(width: BrookieSpace.s1),
        Text('Selected', style: BrookieType.small.copyWith(color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
