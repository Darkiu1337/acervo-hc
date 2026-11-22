import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../service/neural_model_manager.dart';
import '../service/neural_upscale_service.dart';
import '../setting/read_setting.dart';
import 'upscaled_image.dart';

/// Shows [source] immediately and swaps it for the realcugan texture once the
/// neural pass finishes. While the neural result is pending on the visible
/// page, the caller may keep the existing 2x shader as a fallback.
///
/// The widget follows [NeuralUpscaleService.focusIndex] and
/// [NeuralUpscaleService.configRevision]: the visible page and its neighbours
/// are queued, and toggling gallery mode or changing model/scale/denoise
/// immediately re-processes mounted pages.
class NeuralUpscaledImage extends StatefulWidget {
  final ui.Image source;
  final String cacheKey;

  /// Optional local file path / network URL so the service can feed the
  /// original file straight to `realcugan-ncnn-vulkan` without PNG-encoding on
  /// the raster thread.
  final String? sourcePath;
  final String? sourceUrl;

  /// Absolute page index inside the gallery.
  final int index;

  /// Process the page even when it looks black and white, and bypass auto width skip.
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
    this.sourcePath,
    this.sourceUrl,
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
  /// ITU-R BT.601 neutral grayscale color matrix applied on the GPU when the
  /// source page was strict grayscale, removing any slight tint from Real-CUGAN
  /// at zero CPU/memory cost.
  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.299, 0.587, 0.114, 0, 0,
    0.299, 0.587, 0.114, 0, 0,
    0.299, 0.587, 0.114, 0, 0,
    0,     0,     0,     1, 0,
  ]);

  /// Owned clone returned by [NeuralUpscaleService]; disposed on replace/unmount.
  NeuralOutput? _neural;
  int _generation = 0;
  bool _requesting = false;
  bool _inWindow = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    neuralUpscaleService.focusIndex.addListener(_onFocusChanged);
    neuralUpscaleService.windowRevision.addListener(_onWindowRevisionChanged);
    neuralUpscaleService.configRevision.addListener(_onConfigChanged);
    _inWindow = neuralUpscaleService.inWindow(widget.index);
    _isFocused = neuralUpscaleService.focusIndex.value == widget.index;
    _start();
  }

  @override
  void didUpdateWidget(NeuralUpscaledImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.source != widget.source ||
        oldWidget.index != widget.index ||
        oldWidget.forceGrayscale != widget.forceGrayscale ||
        oldWidget.sourcePath != widget.sourcePath ||
        oldWidget.sourceUrl != widget.sourceUrl) {
      _replaceNeural(null);
      _inWindow = neuralUpscaleService.inWindow(widget.index);
      _isFocused = neuralUpscaleService.focusIndex.value == widget.index;
      _start();
    }
  }

  @override
  void dispose() {
    neuralUpscaleService.focusIndex.removeListener(_onFocusChanged);
    neuralUpscaleService.windowRevision.removeListener(_onWindowRevisionChanged);
    neuralUpscaleService.configRevision.removeListener(_onConfigChanged);
    _generation++;
    _replaceNeural(null);
    super.dispose();
  }

  void _replaceNeural(NeuralOutput? next) {
    if (identical(_neural?.image, next?.image)) {
      _neural = next;
      return;
    }
    try {
      _neural?.image.dispose();
    } catch (_) {}
    _neural = next;
  }

  /// Entering the window after the service dropped the page: ask again.
  void _onFocusChanged() {
    if (!mounted) {
      return;
    }
    final bool inWindow = neuralUpscaleService.inWindow(widget.index);
    final bool isFocused = neuralUpscaleService.focusIndex.value == widget.index;
    if (inWindow != _inWindow || isFocused != _isFocused) {
      setState(() {
        _inWindow = inWindow;
        _isFocused = isFocused;
      });
    }
    if (inWindow && _neural == null && !_requesting) {
      _start();
    }
  }

  void _onWindowRevisionChanged() {
    if (!mounted) {
      return;
    }
    final bool inWindow = neuralUpscaleService.inWindow(widget.index);
    if (inWindow != _inWindow) {
      setState(() => _inWindow = inWindow);
    }
    if (inWindow && _neural == null && !_requesting) {
      _start();
    }
  }

  void _onConfigChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _replaceNeural(null);
      _inWindow = neuralUpscaleService.inWindow(widget.index);
      _isFocused = neuralUpscaleService.focusIndex.value == widget.index;
    });
    _start();
  }

  Future<void> _start() async {
    final int generation = ++_generation;

    /// A revisited page usually hits the memory cache: show it on this frame.
    final NeuralOutput? hit = neuralUpscaleService.cachedFor(
      sourceKey: widget.cacheKey,
      width: widget.source.width,
      height: widget.source.height,
    );
    if (hit != null) {
      _replaceNeural(hit);
      return;
    }

    if (!neuralUpscaleService.inWindow(widget.index)) {
      return;
    }

    _requesting = true;
    try {
      await neuralUpscaleService.init();
      if (!mounted ||
          generation != _generation ||
          !neuralModelManager.isModelReady(readSetting.neuralUpscaleModel.value)) {
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
        final NeuralOutput? result = await neuralUpscaleService.upscale(
          NeuralRequest(
            source: source,
            cacheKey: widget.cacheKey,
            index: widget.index,
            frameCount: widget.frameCount,
            forceGrayscale: widget.forceGrayscale,
            sourcePath: widget.sourcePath,
            sourceUrl: widget.sourceUrl,
          ),
        );
        if (!mounted || generation != _generation) {
          try {
            result?.image.dispose();
          } catch (_) {}
          return;
        }
        if (result != null) {
          setState(() => _replaceNeural(result));
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
    final NeuralOutput? neural = _neural;
    if (neural != null) {
      Widget image = RawImage(
        image: neural.image,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        scale: widget.scale,
        filterQuality: FilterQuality.medium,
      );
      if (neural.grayscale) {
        image = ColorFiltered(colorFilter: _grayscaleFilter, child: image);
      }
      return image;
    }

    /// Only the currently visible page pays for the 2x shader fallback while
    /// waiting for Real-CUGAN; off-screen preloaded neighbours wait straight
    /// for the neural result instead of burning GPU/VRAM on temporary textures.
    if (widget.useShaderFallback && _isFocused) {
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
