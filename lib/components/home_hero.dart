import 'dart:math' as math;

import 'package:brookie_babies/components/account_button.dart';
import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/brookie_logo.dart';
import 'package:brookie_babies/widgets/focus_ring.dart';
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
  const HomeHero({super.key, required this.photo, required this.loading, required this.onBook, this.onPhotoFailed});

  /// The photograph, or null while [loading] or if there is none.
  final Uri? photo;

  /// Whether the photograph's link is still being looked up.
  final bool loading;

  final VoidCallback onBook;

  /// Called when [photo] can't be loaded, so the page can offer another.
  /// Until it does, the hero shows the quiet band.
  final VoidCallback? onPhotoFailed;

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  bool _photoFailed = false;

  /// Fits the smallest logo and the button with room around them, so a
  /// phone held sideways still sees the whole composition on one screen.
  static const _minHeight = 360.0;

  @override
  void didUpdateWidget(HomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo != widget.photo) _photoFailed = false;
  }

  void _onPhotoFailed() {
    setState(() => _photoFailed = true);
    widget.onPhotoFailed?.call();
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
              NetworkPhoto(key: ValueKey(photo), url: photo, onFailed: _onPhotoFailed)
            else
              ColoredBox(color: BrookieColors.of(context).surfaceSunk),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(BrookieSpace.s5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BrookieLogo(width: disc / BrookieLogo.discFraction),
                    const SizedBox(height: BrookieSpace.s6),
                    if (onPhoto)
                      _PhotoButton(onPressed: widget.onBook, child: const Text('Book a session'))
                    else
                      FilledButton(onPressed: widget.onBook, child: const Text('Book a session')),
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

/// The butter button on a photograph, with the two-tone focus ring that
/// shows on light and dark photographs alike.
class _PhotoButton extends StatefulWidget {
  const _PhotoButton({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_PhotoButton> createState() => _PhotoButtonState();
}

class _PhotoButtonState extends State<_PhotoButton> {
  bool _focused = false;

  /// Larger than any height the pill can reach, so the ring stays a pill.
  static const _pillRadius = 999.0;

  @override
  Widget build(BuildContext context) {
    return FocusRing.onPhoto(
      visible: _focused,
      borderRadius: _pillRadius,
      child: FilledButton(
        onPressed: widget.onPressed,
        onFocusChange: (focused) => setState(() => _focused = focused),
        style: onPhotoButtonStyle(context),
        child: widget.child,
      ),
    );
  }
}
