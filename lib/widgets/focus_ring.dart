import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Moves keyboard focus to [node] and keeps it well inside the window, so its
/// focus ring (4px outside it) is never cut off at an edge.
///
/// A [TraversalRequestFocusCallback] for the app's traversal policies
/// (MaterialApp.builder and the calendar's days): Tab and the arrow keys
/// call it. Once focused, a control within [BrookieSpace.s6] of the top or
/// bottom of a scroll view, or past it, scrolls to the middle of that view
/// over [kBrookieFadeDuration] (at once with reduced motion). A control
/// already comfortably in view doesn't move the page. Only vertical scroll
/// views scroll: the calendar's month pages stay where they are.
void requestFocusInView(
  FocusNode node, {
  ScrollPositionAlignmentPolicy? alignmentPolicy,
  double? alignment,
  Duration? duration,
  Curve? curve,
}) {
  node.requestFocus();
  final context = node.context;
  final target = context?.findRenderObject();
  if (context == null || target == null || !target.attached) return;
  final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  // Walk out through the scroll views around the control, as
  // Scrollable.ensureVisible does: in each, reveal the box that holds it.
  var inner = context;
  for (var scrollable = Scrollable.maybeOf(inner); scrollable != null; scrollable = Scrollable.maybeOf(inner)) {
    final holder = inner.findRenderObject();
    if (holder != null && holder.attached && scrollable.position.axis == Axis.vertical) {
      _centerUnlessRoomy(scrollable.position, holder, target, still: still);
    }
    inner = scrollable.context;
  }
}

/// How close to a scroll view's edge a focused control may sit before it is
/// scrolled to the middle: its ring, and a card's padding beyond it.
const double _room = BrookieSpace.s6;

void _centerUnlessRoomy(ScrollPosition position, RenderObject holder, RenderObject target, {required bool still}) {
  final viewport = RenderAbstractViewport.maybeOf(holder);
  if (viewport == null || !position.hasPixels || !position.hasContentDimensions) return;
  final bounds = target == holder
      ? target.paintBounds
      : MatrixUtils.transformRect(target.getTransformTo(holder), target.paintBounds);
  final roomy = bounds.inflate(_room);
  // The scroll offsets that put the roomy box's top at the view's top and its
  // bottom at the view's bottom; in between, it is all in view.
  final top = viewport.getOffsetToReveal(holder, 0, rect: roomy, axis: Axis.vertical).offset;
  final bottom = viewport.getOffsetToReveal(holder, 1, rect: roomy, axis: Axis.vertical).offset;
  if (position.pixels >= bottom - 0.5 && position.pixels <= top + 0.5) return;

  final middle = viewport
      .getOffsetToReveal(holder, 0.5, rect: bounds, axis: Axis.vertical)
      .offset
      .clamp(position.minScrollExtent, position.maxScrollExtent);
  if ((middle - position.pixels).abs() < 0.5) return;
  if (still) {
    position.jumpTo(middle);
  } else {
    position.animateTo(middle, duration: kBrookieFadeDuration, curve: Curves.easeOut);
  }
}

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
