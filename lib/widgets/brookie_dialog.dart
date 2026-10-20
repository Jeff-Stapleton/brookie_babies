import 'dart:ui' show SemanticsRole, lerpDouble;

import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/keyboard_input.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';

/// Shows [builder]'s dialog (usually a [BrookieDialog]) the system's way: a
/// 200ms fade, none with reduced motion.
Future<T?> showBrookieDialog<T>(BuildContext context, {required WidgetBuilder builder}) {
  KeyboardInput.listen();
  return showDialog<T>(
    context: context,
    animationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(duration: kBrookieFadeDuration, reverseDuration: kBrookieFadeDuration),
    builder: builder,
  );
}

/// Asks the admin to confirm [title] ("Delete this photo?"), with [message]
/// saying what will happen. Completes with true for [confirmLabel], false
/// for [cancelLabel] or a dismissal.
///
/// A [destructive] confirmation is danger-filled, and focus starts on
/// neither button, so an Enter meant for the page can't confirm it.
Future<bool> showBrookieConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final confirmed = await showBrookieDialog<bool>(
    context,
    builder: (context) => BrookieDialog(
      title: title,
      content: [Text(message)],
      dismissLabel: cancelLabel,
      // Rebuilt when the admin switches between keyboard and mouse, so the
      // ring follows, like the browser's :focus-visible.
      action: ValueListenableBuilder<bool>(
        valueListenable: KeyboardInput.changes,
        builder: (context, lastWasKey, child) => FilledButton(
          autofocus: !destructive,
          style: destructive ? brookieDangerStyle(context) : brookieDialogPrimaryStyle(context),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ),
    ),
  );
  return confirmed ?? false;
}

/// The design system's dialog: a title, a sentence or two, a quiet dismissal
/// on the left and the primary action on the right, on a surface panel that
/// casts the system's dialog shadow.
///
/// Laid out like an [AlertDialog] (whose own Material can't carry that
/// shadow): the title and body scroll on short screens while the actions
/// stay put, and the side padding narrows as the text grows.
class BrookieDialog extends StatelessWidget {
  const BrookieDialog({
    super.key,
    required this.title,
    required this.content,
    required this.dismissLabel,
    required this.action,
    this.contentEdgeToEdge = false,
    this.insetPadding,
  });

  final String title;

  /// The body, in reading text: usually a [Text] or two.
  final List<Widget> content;

  /// Whether [content] spans the panel from edge to edge, without the side
  /// padding the title and actions keep: for a band, such as the date
  /// dialog's calendar on a narrow phone.
  final bool contentEdgeToEdge;

  /// The room between the panel and the window's edges; the theme's when null.
  final EdgeInsets? insetPadding;

  /// The quiet button that closes the dialog with no result.
  final String dismissLabel;

  /// The primary action. A [FilledButton] that takes focus as the dialog
  /// opens should use [brookieDialogPrimaryStyle].
  final Widget action;

  /// Below this window width the actions stack: side by side, "Cancel" and
  /// "Continue with Google" would only just fit, or not at all.
  static const _stackActionsBelow = 380.0;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final dialogTheme = DialogTheme.of(context);
    // As AlertDialog does: from 24px at normal text to 8px at twice the size.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final inset = BrookieSpace.s5 * lerpDouble(1, 1 / 3, clampDouble(textScale, 1, 2) - 1)!;

    final dismiss = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(dismissLabel),
    );
    final actions = MediaQuery.sizeOf(context).width < _stackActionsBelow
        // On a narrow phone, full-width buttons, the primary action first.
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [action, const SizedBox(height: BrookieSpace.s2), dismiss],
          )
        : OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: BrookieSpace.s2,
            overflowAlignment: OverflowBarAlignment.end,
            // If large text still crowds the row, the primary action goes on top.
            overflowDirection: VerticalDirection.up,
            overflowSpacing: BrookieSpace.s2,
            children: [dismiss, action],
          );

    return Dialog(
      // The panel below paints the surface and the shadow.
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: insetPadding,
      semanticsRole: SemanticsRole.alertDialog,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(BrookieRadius.md),
          boxShadow: c.shadowDialog,
        ),
        // Named by its title on every platform; otherwise Android, Windows
        // and Linux screen readers would announce it as "Alert".
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          namesRoute: true,
          label: title,
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Scrolls on short screens rather than overflowing.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(inset, inset, inset, 0),
                          child: DefaultTextStyle(
                            style: dialogTheme.titleTextStyle!,
                            child: Semantics(container: true, child: Text(title)),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            contentEdgeToEdge ? 0 : inset,
                            BrookieSpace.s3,
                            contentEdgeToEdge ? 0 : inset,
                            BrookieSpace.s5,
                          ),
                          child: DefaultTextStyle(
                            style: dialogTheme.contentTextStyle!,
                            child: Semantics(
                              container: true,
                              explicitChildNodes: true,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: content,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(padding: dialogTheme.actionsPadding!, child: actions),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether [states] hold focus that came from the keyboard.
bool _keyboardFocused(Set<WidgetState> states) => states.contains(WidgetState.focused) && KeyboardInput.lastWasKey;

/// The theme's primary button for a dialog's action, ringed for focus only
/// when the visitor is using the keyboard. The dialog focuses its primary
/// action as it opens, and after a click that ring (and the hover fill that
/// comes with it) would make the button look already pressed.
///
/// Build the button in a ValueListenableBuilder on [KeyboardInput.changes],
/// so the ring follows a switch between mouse and keyboard.
ButtonStyle brookieDialogPrimaryStyle(BuildContext context) {
  final c = BrookieColors.of(context);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return c.surfaceSunk;
      if (states.contains(WidgetState.hovered) || _keyboardFocused(states)) return c.inkSoft;
      return c.ink;
    }),
    // BorderSide.none rather than null, which would fall back to the theme's ring.
    side: WidgetStateProperty.resolveWith(
        (states) => _keyboardFocused(states) ? brookieFocusSide(c.focus) : BorderSide.none),
  );
}

/// A destructive primary button ("Delete session"): danger in place of ink,
/// with the theme's focus ring. Like [brookieDialogPrimaryStyle], the ring
/// shows only for keyboard focus.
ButtonStyle brookieDangerStyle(BuildContext context) {
  final c = BrookieColors.of(context);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return c.surfaceSunk;
      return c.danger;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (_keyboardFocused(states)) return brookieFocusSide(c.focus);
      // Hovered, an ink edge, as an outlined button darkens its edge.
      if (states.contains(WidgetState.hovered)) return BorderSide(color: c.ink, width: 1.5);
      return BorderSide.none;
    }),
  );
}
