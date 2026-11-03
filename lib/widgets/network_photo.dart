import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// A photograph from [url], cropped to fill its box. Shows a surface-sunk
/// placeholder until the image has loaded, then fades it in. When
/// [previewUrl] is present, its small image loads first and the original
/// crossfades over it. If neither can be loaded, [errorBuilder] replaces the
/// placeholder and [onFailed] is called.
///
/// Photographs are prints: no rounding, tint or overlay, so none is applied
/// here and callers shouldn't add one.
class NetworkPhoto extends StatefulWidget {
  const NetworkPhoto({
    super.key,
    required this.url,
    this.previewUrl,
    this.alignment = Alignment.center,
    this.fit = BoxFit.cover,
    this.decodeSize,
    this.placeholderBuilder,
    this.errorBuilder,
    this.onFailed,
  }) : assert(fit == BoxFit.cover || fit == BoxFit.contain);

  final Uri url;

  /// A low-resolution version of [url], normally through a private link with
  /// the same expiry. It is fetched before the original to prioritize a useful
  /// first paint on a slow connection.
  final Uri? previewUrl;

  final Alignment alignment;
  final BoxFit fit;

  /// The box the photo fills, in physical pixels, when it is much smaller
  /// than the photo: it is then decoded at just the size that still covers
  /// the box, which saves memory. Null decodes it at full size.
  final Size? decodeSize;

  final WidgetBuilder? placeholderBuilder;
  final WidgetBuilder? errorBuilder;
  final VoidCallback? onFailed;

  @override
  State<NetworkPhoto> createState() => _NetworkPhotoState();
}

class _NetworkPhotoState extends State<NetworkPhoto> {
  late ImageProvider _image;
  ImageProvider? _previewImage;
  bool _previewLoaded = false;
  bool _loaded = false;
  bool _failed = false;

  // The image is resolved here rather than by an Image widget so the fade
  // starts only once each version is decoded, and so a failure can be
  // reported to the parent outside of build.
  Uri? _requested;
  Uri? _requestedPreview;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested != widget.url || _requestedPreview != widget.previewUrl) {
      _load();
    }
  }

  @override
  void didUpdateWidget(NetworkPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.previewUrl != widget.previewUrl) {
      _load();
    } else if (oldWidget.decodeSize != widget.decodeSize ||
        oldWidget.fit != widget.fit) {
      // Same photo at a new size: the Image keeps showing the old decode
      // until the new one is ready (gaplessPlayback), so no fade.
      _image = _provider(widget.url);
    }
  }

  ImageProvider _provider(Uri url) {
    final network = NetworkImage(url.toString());
    final size = widget.decodeSize;
    return size == null
        ? network
        : _FittedSizedImage(network, size, widget.fit);
  }

  Future<void> _load() async {
    final url = _requested = widget.url;
    final previewUrl = _requestedPreview = widget.previewUrl;
    _image = _provider(url);
    _previewImage = previewUrl == null || previewUrl == url
        ? null
        : NetworkImage(previewUrl.toString());
    _previewLoaded = false;
    _loaded = false;
    _failed = false;

    final preview = _previewImage;
    if (preview != null) {
      final failed = await _precache(preview, previewUrl!);
      if (!_isCurrent(url, previewUrl)) return;
      if (!failed) setState(() => _previewLoaded = true);
    }

    final failed = await _precache(_image, url);
    if (!_isCurrent(url, previewUrl)) return;
    if (failed) {
      setState(() => _failed = true);
      widget.onFailed?.call();
    } else {
      setState(() => _loaded = true);
    }
  }

  Future<bool> _precache(ImageProvider image, Uri url) async {
    var failed = false;
    await precacheImage(image, context, onError: (error, stackTrace) {
      failed = true;
      // A private gallery URL carries a one-hour signature in its query.
      // Never copy that credential into logs.
      log('Could not load a photo from ${url.host} (${error.runtimeType})');
    });
    return failed;
  }

  bool _isCurrent(Uri url, Uri? previewUrl) =>
      mounted && url == _requested && previewUrl == _requestedPreview;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : kBrookieFadeDuration;
    final errorBuilder = widget.errorBuilder;
    // Keep an ordinary one-image photograph structurally simple. Besides
    // avoiding an unnecessary layer, callers rely on photographs having no
    // Stack that could be mistaken for a tint, badge or other overlay.
    if (_previewImage == null &&
        widget.placeholderBuilder == null &&
        errorBuilder == null) {
      return ColoredBox(
        color: BrookieColors.of(context).surfaceSunk,
        child: AnimatedOpacity(
          opacity: _loaded ? 1 : 0,
          duration: duration,
          curve: Curves.easeOut,
          child: _loaded
              ? Image(
                  image: _image,
                  fit: widget.fit,
                  alignment: widget.alignment,
                  width: double.infinity,
                  height: double.infinity,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                )
              : const SizedBox.expand(),
        ),
      );
    }
    final showError = _failed && !_previewLoaded && errorBuilder != null;
    final showPlaceholder = !_previewLoaded && !_loaded && !showError;
    return ColoredBox(
      color: BrookieColors.of(context).surfaceSunk,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showPlaceholder)
            widget.placeholderBuilder?.call(context) ?? const SizedBox.expand(),
          AnimatedOpacity(
            opacity: _previewLoaded && !_loaded ? 1 : 0,
            duration: duration,
            curve: Curves.easeOut,
            child: _previewLoaded
                ? Image(
                    image: _previewImage!,
                    fit: widget.fit,
                    alignment: widget.alignment,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  )
                : const SizedBox.expand(),
          ),
          AnimatedOpacity(
            opacity: _loaded ? 1 : 0,
            duration: duration,
            curve: Curves.easeOut,
            child: _loaded
                ? Image(
                    image: _image,
                    fit: widget.fit,
                    alignment: widget.alignment,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  )
                : const SizedBox.expand(),
          ),
          if (showError) errorBuilder(context),
        ],
      ),
    );
  }
}

/// [image] decoded at the smallest size that covers or fits inside [size] the
/// way [fit] does, and never larger than the original.
///
/// [ResizeImage] can only fix the width or fit inside a box, which would leave
/// a landscape photo cropped into a portrait tile too small, and blurred.
@immutable
class _FittedSizedImage extends ImageProvider<_FittedSizedKey> {
  const _FittedSizedImage(this.image, this.size, this.fit);

  final ImageProvider image;
  final Size size;
  final BoxFit fit;

  @override
  Future<_FittedSizedKey> obtainKey(ImageConfiguration configuration) {
    // Stays synchronous when the wrapped key is, so a cached photo shows in
    // the same frame.
    return image
        .obtainKey(configuration)
        .then((key) => _FittedSizedKey(key, size, fit));
  }

  @override
  ImageStreamCompleter loadImage(
      _FittedSizedKey key, ImageDecoderCallback decode) {
    Future<ui.Codec> decodeFitted(ui.ImmutableBuffer buffer,
        {ui.TargetImageSizeCallback? getTargetSize}) {
      return decode(buffer, getTargetSize: (width, height) {
        final scale = fit == BoxFit.cover
            ? math.max(size.width / width, size.height / height)
            : math.min(size.width / width, size.height / height);
        // Only the width: the height follows the photo's own proportions.
        return scale >= 1
            ? const ui.TargetImageSize()
            : ui.TargetImageSize(width: (width * scale).ceil());
      });
    }

    final completer = image.loadImage(key.image, decodeFitted);
    // As ResizeImage does: a photo that failed leaves the cache, so showing
    // it again tries again.
    completer.addEphemeralErrorListener((error, stackTrace) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  @override
  bool operator ==(Object other) =>
      other is _FittedSizedImage &&
      other.image == image &&
      other.size == size &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(image, size, fit);
}

@immutable
class _FittedSizedKey {
  const _FittedSizedKey(this.image, this.size, this.fit);

  final Object image;
  final Size size;
  final BoxFit fit;

  @override
  bool operator ==(Object other) =>
      other is _FittedSizedKey &&
      other.image == image &&
      other.size == size &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(image, size, fit);
}
