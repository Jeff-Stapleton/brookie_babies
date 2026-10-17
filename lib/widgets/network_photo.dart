import 'dart:developer';

import 'package:brookie_babies/theme/brookie_theme.dart';
import 'package:flutter/material.dart';

/// A photograph from [url], cropped to fill its box. Shows a surface-sunk
/// placeholder until the image has loaded, then fades it in; if it can't be
/// loaded the placeholder stays and [onFailed] is called.
///
/// Photographs are prints: no rounding, tint or overlay, so none is applied
/// here and callers shouldn't add one.
class NetworkPhoto extends StatefulWidget {
  const NetworkPhoto({super.key, required this.url, this.alignment = Alignment.center, this.onFailed});

  final Uri url;
  final Alignment alignment;
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
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final url = _requested = widget.url;
    _image = NetworkImage(url.toString());
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
