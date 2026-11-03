import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:acervo_hc/src/service/upscale_service.dart';

/// Displays [source] immediately and swaps it for the 2x upscaled texture once
/// the shader pipeline finishes. While processing (or if it fails) the original
/// image stays visible, so zooming never waits for the upscale.
class UpscaledImage extends StatefulWidget {
  final ui.Image source;

  /// Cache key of the upscaled texture, usually the image url or path.
  final String cacheKey;

  final double? width;
  final double? height;
  final BoxFit fit;
  final double scale;

  const UpscaledImage({
    Key? key,
    required this.source,
    required this.cacheKey,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.scale = 1.0,
  }) : super(key: key);

  @override
  State<UpscaledImage> createState() => _UpscaledImageState();
}

class _UpscaledImageState extends State<UpscaledImage> {
  /// Cached by [UpscaleService]; this state never disposes it.
  ui.Image? _upscaled;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(UpscaledImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey || oldWidget.source != widget.source) {
      _upscaled = null;
      _start();
    }
  }

  Future<void> _start() async {
    final int generation = ++_generation;

    _upscaled = upscaleService.cached(widget.cacheKey);
    if (_upscaled != null) {
      return;
    }

    final String key = widget.cacheKey;

    /// The image cache may dispose the decoded image while the shader runs.
    final ui.Image source;
    try {
      source = widget.source.clone();
    } catch (_) {
      return;
    }

    final ui.Image? result = await upscaleService.upscale(source, key);
    source.dispose();

    if (!mounted || generation != _generation) {
      return;
    }

    if (result != null) {
      setState(() => _upscaled = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawImage(
      image: _upscaled ?? widget.source,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      scale: widget.scale,
      filterQuality: FilterQuality.medium,
    );
  }
}
