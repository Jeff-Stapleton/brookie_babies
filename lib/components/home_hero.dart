import 'dart:math' as math;

import 'package:brookie_babies/components/account_button.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/network_photo.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The home page's first screen: one full-bleed photograph with the logo
/// centered on it and "Book a session" below the logo.
///
/// Without a photograph (none uploaded, or it failed to load) the same
/// composition sits on a quiet band, with the primary button in place of the
/// butter one, which is only for photographs.
class HomeHero extends StatefulWidget {
  const HomeHero({super.key, required this.photo, required this.loading, required this.onBook});

  /// The photograph, or null while [loading] or if there is none.
  final Uri? photo;

  /// Whether the photograph's link is still being looked up.
  final bool loading;

  final VoidCallback onBook;

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  bool _photoFailed = false;

  /// Fits the smallest logo and the button with room around them, so a
  /// phone held sideways still sees the whole composition on one screen.
  static const _minHeight = 360.0;

  /// The logo's disc is this fraction of assets/logo.png's width; the
  /// lettering overhangs it. The design system sizes the logo by its disc.
  static const _discFraction = 0.73;

  @override
  void didUpdateWidget(HomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo != widget.photo) _photoFailed = false;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = math.max(size.height, _minHeight);
    // 180–280px across, growing with the window but leaving room below for
    // the button when the window is short.
    final disc = clampDouble(math.min(size.width * 0.56, height * 0.34), 180, 280);
    final inset = size.width >= BrookieBreakpoint.gutter ? BrookieSpace.s5 : BrookieSpace.s4;

    final photo = widget.photo;
    final onPhoto = widget.loading || (photo != null && !_photoFailed);

    return Semantics(
      container: true,
      label: 'Brooke Stapleton Photography',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null)
              NetworkPhoto(url: photo, onFailed: () => setState(() => _photoFailed = true))
            else
              ColoredBox(color: BrookieColors.of(context).surfaceSunk),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(BrookieSpace.s5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Used exactly as supplied: never recolored, cropped or redrawn.
                    Image.asset('assets/logo.png', width: disc / _discFraction, excludeFromSemantics: true),
                    if (onPhoto) ...[
                      const SizedBox(height: BrookieSpace.s6 - _PhotoButton.ringSpace),
                      _PhotoButton(onPressed: widget.onBook, child: const Text('Book a session')),
                    ] else ...[
                      const SizedBox(height: BrookieSpace.s6),
                      FilledButton(onPressed: widget.onBook, child: const Text('Book a session')),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(top: inset, right: inset, child: AccountButton(onPhoto: onPhoto)),
          ],
        ),
      ),
    );
  }
}

/// The butter button on a photograph. Its focus ring is two-tone, on-butter
/// inside and butter outside, so it shows on light and dark photographs
/// alike; a butter ring alone on a butter button only looks like a slightly
/// bigger button.
class _PhotoButton extends StatefulWidget {
  const _PhotoButton({required this.onPressed, required this.child});

  /// Room for the focus ring, kept when unfocused so focus moves nothing.
  static const ringSpace = 4.0;

  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_PhotoButton> createState() => _PhotoButtonState();
}

class _PhotoButtonState extends State<_PhotoButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = BrookieColors.of(context);
    final style = onPhotoButtonStyle(context).copyWith(
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: c.onButter, width: 2, strokeAlign: BorderSide.strokeAlignOutside);
        }
        if (states.contains(WidgetState.hovered)) return BorderSide(color: c.onButter, width: 1.5);
        return null;
      }),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: _focused ? c.butter : Colors.transparent, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_PhotoButton.ringSpace),
        child: FilledButton(
          onPressed: widget.onPressed,
          onFocusChange: (focused) => setState(() => _focused = focused),
          style: style,
          child: widget.child,
        ),
      ),
    );
  }
}
