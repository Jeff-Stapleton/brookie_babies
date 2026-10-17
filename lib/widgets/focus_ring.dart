import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// The keyboard focus ring for controls the Material theme doesn't style: a
/// 2px gap, then a solid 2px ring in [BrookieColors.focus].
///
/// It paints outside [child] and takes no layout space, so showing it moves
/// nothing. Show it only for keyboard focus (FocusableActionDetector's
/// `onShowFocusHighlight`), never for a tap.
class FocusRing extends StatelessWidget {
  const FocusRing({super.key, required this.visible, this.borderRadius, required this.child})
      : _circle = false;

  /// A ring for a round [child], such as a calendar day.
  const FocusRing.circle({super.key, required this.visible, required this.child})
      : borderRadius = null,
        _circle = true;

  final bool visible;

  /// [child]'s corner radius; the ring's corners follow it at the gap.
  final double? borderRadius;
  final Widget child;
  final bool _circle;

  static const _gap = 2.0;
  static const _width = 2.0;
  static const _outset = _gap + _width;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        child,
        if (visible)
          Positioned(
            left: -_outset,
            top: -_outset,
            right: -_outset,
            bottom: -_outset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: _circle ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: _circle ? null : BorderRadius.circular((borderRadius ?? 0) + _outset),
                  border: Border.all(color: BrookieColors.of(context).focus, width: _width),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
