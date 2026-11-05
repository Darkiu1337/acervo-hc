import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../service/neural_model_manager.dart';
import '../service/neural_upscale_service.dart';
import 'upscaled_image.dart';

/// Shows [source] immediately and swaps it for the realcugan texture once the
/// neural pass finishes. While the neural result is pending, the caller may
/// keep the existing 2x shader as a fallback.
///
/// The widget follows [NeuralUpscaleService.focusIndex]: the visible page and
/// its neighbours are queued, and a page that comes back into range asks again
/// after the service dropped it.
class NeuralUpscaledImage extends StatefulWidget {
  final ui.Image source;
  final String cacheKey;

  /// Absolute page index inside the gallery.
  final int index;

  /// Process the page even when it looks black and white.
  final bool forceGrayscale;

  final int frameCount;
  final bool useShaderFallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double scale;

  const NeuralUpscaledImage({
    Key? key,
    required this.source,
    required this.cacheKey,
    this.index = 0,
    this.forceGrayscale = false,
    this.frameCount = 1,
    this.useShaderFallback = false,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.scale = 1.0,
  }) : super(key: key);

  @override
  State<NeuralUpscaledImage> createState() => _NeuralUpscaledImageState();
}

class _NeuralUpscaledImageState extends State<NeuralUpscaledImage> {
  /// Cached by [NeuralUpscaleService]; this state never disposes it.
  ui.Image? _neural;
  int _generation = 0;
  bool _requesting = false;
  bool _inWindow = false;

  @override
  void initState() {
    super.initState();
    neuralUpscaleService.focusIndex.addListener(_onFocusChanged);
    neuralUpscaleService.windowRevision.addListener(_onFocusChanged);
    _inWindow = neuralUpscaleService.inWindow(widget.index);
    _start();
  }

  @override
  void didUpdateWidget(NeuralUpscaledImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.source != widget.source ||
        oldWidget.index != widget.index ||
        oldWidget.forceGrayscale != widget.forceGrayscale) {
      _neural = null;
      _inWindow = neuralUpscaleService.inWindow(widget.index);
      _start();
    }
  }

  @override
  void dispose() {
    neuralUpscaleService.focusIndex.removeListener(_onFocusChanged);
    neuralUpscaleService.windowRevision.removeListener(_onFocusChanged);
    _generation++;
    super.dispose();
  }

  /// Entering the window after the service dropped the page: ask again.
  void _onFocusChanged() {
    if (!mounted) {
      return;
    }
    final bool inWindow = neuralUpscaleService.inWindow(widget.index);
    if (inWindow == _inWindow) {
      return;
    }
    setState(() => _inWindow = inWindow);
    if (inWindow && _neural == null && !_requesting) {
      _start();
    }
  }

  Future<void> _start() async {
    final int generation = ++_generation;

    /// A revisited page usually hits the memory cache: show it on this frame.
    _neural = neuralUpscaleService.cachedFor(
      sourceKey: widget.cacheKey,
      width: widget.source.width,
      height: widget.source.height,
    );
    if (_neural != null) {
      return;
    }

    if (!neuralUpscaleService.inWindow(widget.index)) {
      return;
    }

    _requesting = true;
    try {
      await neuralUpscaleService.init();
      if (!mounted || generation != _generation || !neuralModelManager.isReady) {
        return;
      }

      /// The image cache may dispose the decoded image while the process runs.
      final ui.Image source;
      try {
        source = widget.source.clone();
      } catch (_) {
        return;
      }

      try {
        final ui.Image? result = await neuralUpscaleService.upscale(
          NeuralRequest(
            source: source,
            cacheKey: widget.cacheKey,
            index: widget.index,
            frameCount: widget.frameCount,
            forceGrayscale: widget.forceGrayscale,
          ),
        );
        if (!mounted || generation != _generation) {
          return;
        }
        if (result != null) {
          setState(() => _neural = result);
        }
      } finally {
        source.dispose();
      }
    } finally {
      if (generation == _generation) {
        _requesting = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? neural = _neural;
    if (neural != null) {
      return RawImage(
        image: neural,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        scale: widget.scale,
        filterQuality: FilterQuality.medium,
      );
    }

    /// Only the pages close to the visible one pay for the shader texture.
    if (widget.useShaderFallback && _inWindow) {
      return UpscaledImage(
        source: widget.source,
        cacheKey: widget.cacheKey,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        scale: widget.scale,
      );
    }

    return RawImage(
      image: widget.source,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      scale: widget.scale,
      filterQuality: FilterQuality.medium,
    );
  }
}
