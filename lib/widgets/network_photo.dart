import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// A photograph from [url], cropped to fill its box. Shows a surface-sunk
/// placeholder until the image has loaded, then fades it in; if it can't be
/// loaded the placeholder stays and [onFailed] is called.
///
/// Photographs are prints: no rounding, tint or overlay, so none is applied
/// here and callers shouldn't add one.
class NetworkPhoto extends StatefulWidget {
  const NetworkPhoto({
    super.key,
    required this.url,
    this.alignment = Alignment.center,
    this.decodeSize,
    this.onFailed,
  });

  final Uri url;
  final Alignment alignment;

  /// The box the photo fills, in physical pixels, when it is much smaller
  /// than the photo: it is then decoded at just the size that still covers
  /// the box, which saves memory. Null decodes it at full size.
  final Size? decodeSize;

  final VoidCallback? onFailed;

  @override
  State<NetworkPhoto> createState() => _NetworkPhotoState();
}

class _NetworkPhotoState extends State<NetworkPhoto> {
  late ImageProvider _image;
  bool _loaded = false;

  // The image is resolved here rather than by an Image widget so the fade
  // starts only once the whole photo is decoded, and so a failure can be
  // reported to the parent outside of build.
  Uri? _requested;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested != widget.url) _load();
  }

  @override
  void didUpdateWidget(NetworkPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _load();
    } else if (oldWidget.decodeSize != widget.decodeSize) {
      // Same photo at a new size: the Image keeps showing the old decode
      // until the new one is ready (gaplessPlayback), so no fade.
      _image = _provider();
    }
  }

  ImageProvider _provider() {
    final network = NetworkImage(widget.url.toString());
    final size = widget.decodeSize;
    return size == null ? network : _CoverSizedImage(network, size);
  }

  Future<void> _load() async {
    final url = _requested = widget.url;
    _image = _provider();
    _loaded = false;
    var failed = false;
    await precacheImage(_image, context, onError: (error, stackTrace) {
      failed = true;
      log('Could not load photo $url: $error');
    });
    if (!mounted || url != _requested) return;
    if (failed) {
      widget.onFailed?.call();
    } else {
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BrookieColors.of(context).surfaceSunk,
      child: AnimatedOpacity(
        opacity: _loaded ? 1 : 0,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : kBrookieFadeDuration,
        curve: Curves.easeOut,
        child: _loaded
            ? Image(
                image: _image,
                fit: BoxFit.cover,
                alignment: widget.alignment,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                excludeFromSemantics: true,
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

/// [image] decoded at the smallest size that still covers [size] the way
/// [BoxFit.cover] fills it, and never larger than the original.
///
/// [ResizeImage] can only fix the width or fit inside a box, which would leave
/// a landscape photo cropped into a portrait tile too small, and blurred.
@immutable
class _CoverSizedImage extends ImageProvider<_CoverSizedKey> {
  const _CoverSizedImage(this.image, this.size);

  final ImageProvider image;
  final Size size;

  @override
  Future<_CoverSizedKey> obtainKey(ImageConfiguration configuration) {
    // Stays synchronous when the wrapped key is, so a cached photo shows in
    // the same frame.
    return image.obtainKey(configuration).then((key) => _CoverSizedKey(key, size));
  }

  @override
  ImageStreamCompleter loadImage(_CoverSizedKey key, ImageDecoderCallback decode) {
    Future<ui.Codec> decodeCovering(ui.ImmutableBuffer buffer, {ui.TargetImageSizeCallback? getTargetSize}) {
      return decode(buffer, getTargetSize: (width, height) {
        final scale = math.max(size.width / width, size.height / height);
        // Only the width: the height follows the photo's own proportions.
        return scale >= 1 ? const ui.TargetImageSize() : ui.TargetImageSize(width: (width * scale).ceil());
      });
    }

    final completer = image.loadImage(key.image, decodeCovering);
    // As ResizeImage does: a photo that failed leaves the cache, so showing
    // it again tries again.
    completer.addEphemeralErrorListener((error, stackTrace) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  @override
  bool operator ==(Object other) => other is _CoverSizedImage && other.image == image && other.size == size;

  @override
  int get hashCode => Object.hash(image, size);
}

@immutable
class _CoverSizedKey {
  const _CoverSizedKey(this.image, this.size);

  final Object image;
  final Size size;

  @override
  bool operator ==(Object other) => other is _CoverSizedKey && other.image == image && other.size == size;

  @override
  int get hashCode => Object.hash(image, size);
}
