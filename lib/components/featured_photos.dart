import 'dart:math' as math;

import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/network_photo.dart';
import 'package:flutter/material.dart';

/// A few photographs laid on paper as prints: square corners, a soft print
/// shadow (none in Darkroom), portrait 4:5 crops in a grid of full rows.
/// Shows nothing for fewer than two [photos].
class FeaturedPhotos extends StatelessWidget {
  const FeaturedPhotos({super.key, required this.photos, this.padding = EdgeInsets.zero});

  final List<Uri> photos;

  /// Space around the grid, left out along with it when it isn't shown.
  final EdgeInsetsGeometry padding;

  static const maxCount = 6;

  @override
  Widget build(BuildContext context) {
    var columns = MediaQuery.sizeOf(context).width >= BrookieBreakpoint.gutter ? 3 : 2;
    var count = math.min(photos.length, maxCount);
    // Two photos on a wide screen make a pair; a single one would fill the
    // whole column, so it is left out.
    columns = math.min(columns, count);
    if (columns < 2) return const SizedBox.shrink();
    // Only full rows: a lone print on the last row looks like a mistake.
    count -= count % columns;

    final shadow = BrookieColors.of(context).shadowPrint;
    final rows = [
      for (var start = 0; start < count; start += columns)
        Row(
          children: [
            for (var i = start; i < start + columns; i++) ...[
              if (i > start) const SizedBox(width: BrookieSpace.s4),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: shadow),
                  child: AspectRatio(aspectRatio: 4 / 5, child: NetworkPhoto(url: photos[i])),
                ),
              ),
            ],
          ],
        ),
    ];

    return Padding(
      padding: padding,
      child: Semantics(
        container: true,
        label: 'Photographs by Brooke Stapleton',
        child: Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: BrookieSpace.s4),
              rows[r],
            ],
          ],
        ),
      ),
    );
  }
}
