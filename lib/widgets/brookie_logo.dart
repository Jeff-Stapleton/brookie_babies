import 'package:flutter/material.dart';

/// The studio's logo, used exactly as supplied: never recolored, cropped or
/// redrawn. Decorative: the page around it names the studio.
///
/// It takes its full size before the file has loaded, so nothing around it
/// moves when it appears.
class BrookieLogo extends StatelessWidget {
  const BrookieLogo({super.key, required this.width});

  final double width;

  static const asset = 'assets/logo.png';

  /// Width over height of [asset] (551 x 453 pixels).
  static const aspectRatio = 551 / 453;

  /// The disc's share of [asset]'s width; the lettering overhangs it. The
  /// design system sizes the logo by its disc.
  static const discFraction = 0.73;

  @override
  Widget build(BuildContext context) {
    return Image.asset(asset, width: width, height: width / aspectRatio, excludeFromSemantics: true);
  }
}
