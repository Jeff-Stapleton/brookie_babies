import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// The keyboard focus ring for controls the Material theme doesn't style: a
/// 2px gap, then a solid 2px ring in [BrookieColors.focus].
///
/// It paints outside [child] and takes no layout space, so showing it moves
/// nothing. Show it only for keyboard focus (FocusableActionDetector's
/// `onShowFocusHighlight`), never for a tap.
class FocusRing extends StatelessWidget {
  const FocusRing({super.key, required this.visible, this.borderRadius, this.color, required this.child})
      : _circle = false,
        _onPhoto = false;

  /// A ring for a round [child], such as a calendar day.
  const FocusRing.circle({super.key, required this.visible, this.color, required this.child})
      : borderRadius = null,
        _circle = true,
        _onPhoto = false;

  /// A ring for a control on a photograph, where the ink ring alone can
  /// vanish into a dark print: 2px of [BrookieColors.onButter] against the
  /// control, then 2px of [BrookieColors.butter], so one band always shows,
  /// on light and dark photographs and in both themes.
  const FocusRing.onPhoto({super.key, required this.visible, this.borderRadius, bool circle = false, required this.child})
      : color = null,
        _circle = circle,
        _onPhoto = true;

  final bool visible;

  /// [child]'s corner radius; the ring's corners follow it at the gap.
  final double? borderRadius;

  /// The ring's color. Defaults to [BrookieColors.focus]; on a butter fill,
  /// pass [BrookieColors.onButter], since light ink barely shows on butter in
  /// Darkroom.
  final Color? color;

  final Widget child;
  final bool _circle;
  final bool _onPhoto;

  static const _gap = 2.0;
  static const _width = 2.0;
  static const _outset = _gap + _width;

  Widget _ring(double outset, Color color) {
    return Positioned(
      left: -outset,
      top: -outset,
      right: -outset,
      bottom: -outset,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: _circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: _circle ? null : BorderRadius.circular((borderRadius ?? 0) + outset),
            border: Border.all(color: color, width: _width),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        child,
        if (visible && _onPhoto) ...[
          _ring(_width, c.onButter),
          _ring(2 * _width, c.butter),
        ] else if (visible)
          _ring(_outset, color ?? c.focus),
      ],
    );
  }
}
