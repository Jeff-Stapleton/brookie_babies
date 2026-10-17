import 'dart:math' as math;

import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:brookie_babies/widgets/network_photo.dart';
import 'package:flutter/material.dart';

/// A few photographs laid on paper as prints: square corners, a soft print
/// shadow (none in Darkroom), portrait 4:5 crops in a grid of full rows.
/// Shows nothing for fewer than two [photos].
class FeaturedPhotos extends StatelessWidget {
  const FeaturedPhotos({super.key, required this.photos, this.padding = EdgeInsets.zero, this.onPhotoFailed});

  final List<Uri> photos;

  /// Space around the grid, left out along with it when it isn't shown.
  final EdgeInsetsGeometry padding;

  /// Called with a photo that can't be loaded, so the page can leave it out.
  final ValueChanged<Uri>? onPhotoFailed;

  static const maxCount = 6;

  static const _gap = BrookieSpace.s4;
  static const _aspectRatio = 4 / 5;

  /// Tiles decode in steps of this many physical pixels, so resizing the
  /// window only decodes them again now and then.
  static const _decodeStep = 256;

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
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    return Padding(
      padding: padding,
      child: Semantics(
        container: true,
        label: 'Photographs by Brooke Stapleton',
        child: LayoutBuilder(builder: (context, constraints) {
          // Decode each photo at about the size of its tile, not the camera's.
          final tileWidth = (constraints.maxWidth - _gap * (columns - 1)) / columns;
          final decodeWidth = ((tileWidth * pixelRatio / _decodeStep).ceil() * _decodeStep).toDouble();
          final decodeSize = Size(decodeWidth, decodeWidth / _aspectRatio);

          Widget tile(Uri photo) => DecoratedBox(
                decoration: BoxDecoration(boxShadow: shadow),
                child: AspectRatio(
                  aspectRatio: _aspectRatio,
                  child: NetworkPhoto(
                    // Keyed by photo, so a photo left out doesn't hand its
                    // state to the next one.
                    key: ValueKey(photo),
                    url: photo,
                    decodeSize: decodeSize,
                    onFailed: () => onPhotoFailed?.call(photo),
                  ),
                ),
              );

          return Column(
            children: [
              for (var start = 0; start < count; start += columns) ...[
                if (start > 0) const SizedBox(height: _gap),
                Row(
                  children: [
                    for (var i = start; i < start + columns; i++) ...[
                      if (i > start) const SizedBox(width: _gap),
                      Expanded(child: tile(photos[i])),
                    ],
                  ],
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}
