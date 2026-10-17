import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/utilities/keyboard_input.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
import 'package:flutter/material.dart';

/// Google's own sign-in button, "Continue with Google", in place of the
/// dialog's primary button (the Dialog spec: "Its look is set by Google's
/// branding rules, not by this system").
///
/// Drawn from Google's sign-in button assets: the official G mark (rendered
/// from Google's SVG to assets/google/), Google's fill, edge and label
/// colors, a pill, Roboto Medium at 14px, and Google's spacing: 12px, the
/// 20px G, 10px, the label, 12px. Print uses Google's light scheme, which
/// keeps an edge on the white dialog; Darkroom its dark scheme.
///
/// It is 52px tall rather than Google's 40, so it sits level with the
/// dialog's "Cancel"; the mark, label and spacing keep Google's sizes.
///
/// Roboto is the web engine's built-in fallback font, so it needs no
/// bundling, but the engine loads only its regular weight: the label
/// renders in Roboto Regular unless Roboto Medium is bundled.
///
/// Focused, it keeps Google's edge and draws the system's ring outside it
/// (a 2px gap, then 2px), and only for keyboard focus: the dialog focuses it
/// as it opens, and after a click a ring would make it look pressed.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onPressed, this.autofocus = false});

  final VoidCallback onPressed;
  final bool autofocus;

  /// One of the labels Google's branding rules allow.
  static const label = 'Continue with Google';

  /// Google's G, at 20px with 2x, 3x and 4x variants.
  static const logo = AssetImage('assets/google/g_logo.png');

  static const _logoSize = 20.0;
  static const _logoGap = 10.0;
  static const _padding = 12.0;

  /// Google's label type. Brand typography, so not a [BrookieType] style.
  static const _labelStyle = TextStyle(
    fontFamily: 'Roboto',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0.25,
    leadingDistribution: TextLeadingDistribution.even,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).brightness == Brightness.dark ? _GoogleColors.dark : _GoogleColors.light;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Rebuilt when the family switches between keyboard and mouse, so the
    // ring follows, like the browser's :focus-visible.
    return ValueListenableBuilder<bool>(
      valueListenable: KeyboardInput.changes,
      builder: (context, lastWasKey, _) {
        bool keyboardFocused(Set<WidgetState> states) => states.contains(WidgetState.focused) && lastWasKey;
        return FilledButton(
          autofocus: autofocus,
          onPressed: onPressed,
          // The ring paints outside the button.
          clipBehavior: Clip.none,
          style: ButtonStyle(
            // Google's state layer over its fill: 8% on hover, 12% pressed
            // or keyboard-focused.
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              final layer = states.contains(WidgetState.pressed) || keyboardFocused(states)
                  ? 0.12
                  : states.contains(WidgetState.hovered)
                      ? 0.08
                      : 0.0;
              return Color.alphaBlend(scheme.stateLayer.withValues(alpha: layer), scheme.fill);
            }),
            foregroundColor: WidgetStatePropertyAll(scheme.label),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            // Google's 1px edge, focused or not.
            side: WidgetStatePropertyAll(BorderSide(color: scheme.edge)),
            backgroundBuilder: (context, states, child) => FocusRing(
              visible: keyboardFocused(states),
              // Any radius past half the height draws a pill.
              borderRadius: BrookieSize.control,
              child: child!,
            ),
            elevation: const WidgetStatePropertyAll(0),
            shape: const WidgetStatePropertyAll(StadiumBorder()),
            minimumSize: const WidgetStatePropertyAll(Size(0, BrookieSize.control)),
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: _padding)),
            textStyle: const WidgetStatePropertyAll(_labelStyle),
            animationDuration: reduceMotion ? Duration.zero : kBrookieStateDuration,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Part of the button's name, not an image of its own.
              const Image(image: logo, width: _logoSize, height: _logoSize, excludeFromSemantics: true),
              const SizedBox(width: _logoGap),
              // Wraps rather than truncates with large text.
              const Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          ),
        );
      },
    );
  }
}

/// Google's colors for its sign-in button, from Google's sign-in button
/// assets (fill, 1px edge, label) and its button CSS (the state layer). A
/// third-party brand's colors, set by Google's branding rules, so the one
/// documented exception to taking colors from [BrookieColors].
class _GoogleColors {
  const _GoogleColors({required this.fill, required this.edge, required this.label, required this.stateLayer});

  final Color fill;
  final Color edge;
  final Color label;
  final Color stateLayer;

  /// Google's light scheme, for Print.
  static const light = _GoogleColors(
    fill: Color(0xFFFFFFFF),
    edge: Color(0xFF747775),
    label: Color(0xFF1F1F1F),
    stateLayer: Color(0xFF303030),
  );

  /// Google's dark scheme, for Darkroom.
  static const dark = _GoogleColors(
    fill: Color(0xFF131314),
    edge: Color(0xFF8E918F),
    label: Color(0xFFE3E3E3),
    stateLayer: Color(0xFFFFFFFF),
  );
}
