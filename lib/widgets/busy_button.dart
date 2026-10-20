import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// Which of the theme's buttons a [BusyButton] is.
enum BusyButtonKind {
  /// The view's primary (ink) button.
  filled,
  outlined,

  /// A quiet one, such as "Delete all photos" beside a list.
  text,
}

/// A button whose action takes a while: while [busy] it says so
/// ([busyLabel], with a small spinner) and looks unavailable, but stays
/// enabled.
///
/// A disabled button would drop keyboard focus mid-action (onto whatever
/// is next, where a second Enter would do something else), so a busy one
/// keeps it and ignores presses until the action ends, like BookingCard's
/// download. Null [onPressed] disables it as usual.
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
    this.kind = BusyButtonKind.outlined,
    this.icon,
    this.focusNode,
  });

  final String label;

  /// What it says while [busy]: "Saving changes…".
  final String busyLabel;

  final bool busy;
  final VoidCallback? onPressed;
  final BusyButtonKind kind;
  final IconData? icon;
  final FocusNode? focusNode;

  /// Looks disabled (surface-sunk, ink-soft) but keeps focus, and with it
  /// the theme's ring (an outlined button keeps its edge inside it).
  ButtonStyle? _busyStyle(BrookieColors c) {
    if (!busy) return null;
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(kind == BusyButtonKind.filled ? c.surfaceSunk : Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(c.inkSoft),
      iconColor: WidgetStatePropertyAll(c.inkSoft),
      side: kind == BusyButtonKind.outlined ? WidgetStatePropertyAll(BorderSide(color: c.line, width: 1.5)) : null,
      mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.progress),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final onPressed = this.onPressed;
    final icon = this.icon;
    final Widget? iconWidget = busy
        ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.inkSoft))
        : (icon == null ? null : Icon(icon));
    final text = Text(busy ? busyLabel : label);
    // Pressing it again while busy does nothing.
    final VoidCallback? press = onPressed == null ? null : (busy ? () {} : onPressed);
    final style = _busyStyle(c);
    final button = switch (kind) {
      BusyButtonKind.filled =>
        FilledButton.icon(onPressed: press, focusNode: focusNode, style: style, icon: iconWidget, label: text),
      BusyButtonKind.outlined =>
        OutlinedButton.icon(onPressed: press, focusNode: focusNode, style: style, icon: iconWidget, label: text),
      BusyButtonKind.text =>
        TextButton.icon(onPressed: press, focusNode: focusNode, style: style, icon: iconWidget, label: text),
    };
    // One node and a live region, so screen readers hear the busy label and
    // then the button's name again.
    return MergeSemantics(child: Semantics(liveRegion: true, child: button));
  }
}
