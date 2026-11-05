import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../service/neural_model_manager.dart';
import '../service/neural_upscale_service.dart';
import 'upscaled_image.dart';

/// Shows [source] immediately and swaps it for the realcugan texture once the
/// neural pass finishes. While the neural result is pending, the caller may
/// keep the existing 2x shader as a fallback.
class NeuralUpscaledImage extends StatefulWidget {
  final ui.Image source;
  final String cacheKey;
  final int frameCount;
  final bool priority;
  final bool useShaderFallback;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double scale;

  const NeuralUpscaledImage({
    Key? key,
    required this.source,
    required this.cacheKey,
    this.frameCount = 1,
    this.priority = false,
    this.useShaderFallback = true,
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

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(NeuralUpscaledImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.source != widget.source) {
      _neural = null;
      _start();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _start() async {
    final int generation = ++_generation;
    final String key = widget.cacheKey;

    _neural = neuralUpscaleService.cached(key);
    if (_neural != null) {
      return;
    }

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
          cacheKey: key,
          priority: widget.priority,
          frameCount: widget.frameCount,
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

    if (widget.useShaderFallback) {
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
