import 'dart:async';
import 'dart:ui' as ui;

import 'package:acervo_hc/src/service/log.dart';

/// Builds a 2x upscaled copy of a decoded page image so zoomed pages stay
/// crisp.
///
/// Only the visible page (and its preloaded neighbour) is ever processed, and
/// results are kept in a small LRU cache because every 2x RGBA texture is
/// roughly four times the source size in bytes.
class UpscaleService {
  UpscaleService._();

  static const String _bicubicShader = 'assets/shaders/upscale/bicubic_x2.frag';
  static const String _casShader = 'assets/shaders/upscale/cas.frag';

  /// Never build a texture larger than this on any axis (VRAM guard).
  static const int _maxOutputDimension = 4096;

  /// Rough budget for the cache of upscaled textures.
  static const int _maxCacheBytes = 192 * 1024 * 1024;

  /// CAS strength, 0.0 (off) to 1.0 (maximum). 0.45 keeps text crisp without
  /// visible halos on JPEG pages.
  static const double _sharpness = 0.45;

  Future<List<ui.FragmentProgram>>? _programsFuture;
  Future<void> _queue = Future<void>.value();

  final Map<String, ui.Image> _cache = <String, ui.Image>{};
  final Map<String, Future<ui.Image?>> _pending = <String, Future<ui.Image?>>{};
  final List<String> _lru = <String>[];
  int _cacheBytes = 0;

  /// Returns the cached 2x image for [key], if it is still around.
  ui.Image? cached(String key) {
    final ui.Image? image = _cache[key];
    if (image == null) {
      return null;
    }
    _touch(key);
    return image;
  }

  /// Drops every cached texture. Called when the reading page closes; the
  /// images themselves are released by the engine once nothing paints them.
  void clearCache() {
    _cache.clear();
    _lru.clear();
    _cacheBytes = 0;
  }

  /// Returns a 2x upscaled copy of [source], cached by [key], or `null` when
  /// the pipeline cannot run.
  ///
  /// Calls are serialised: each chain keeps two textures alive until the final
  /// read-back, so running several chains at once would multiply GPU memory.
  Future<ui.Image?> upscale(ui.Image source, String key) {
    final ui.Image? hit = cached(key);
    if (hit != null) {
      return Future<ui.Image?>.value(hit);
    }

    final Future<ui.Image?>? pending = _pending[key];
    if (pending != null) {
      return pending;
    }

    final Future<ui.Image?> future = _enqueue(source, key);
    _pending[key] = future;
    return future.whenComplete(() => _pending.remove(key));
  }

  Future<ui.Image?> _enqueue(ui.Image source, String key) {
    final Future<void> previous = _queue;
    final Completer<ui.Image?> completer = Completer<ui.Image?>();

    _queue = () async {
      await previous;
      try {
        completer.complete(await _run(source, key));
      } catch (e, s) {
        completer.completeError(e, s);
      }
    }();

    return completer.future;
  }

  Future<ui.Image?> _run(ui.Image source, String key) async {
    final int width = source.width;
    final int height = source.height;
    if (width <= 0 || height <= 0) {
      return null;
    }

    /// 2x, capped so huge source images do not allocate a gigantic texture.
    final int largestSide = width > height ? width : height;
    final double factor = _maxOutputDimension / largestSide < 2.0 ? _maxOutputDimension / largestSide : 2.0;
    final int outputWidth = (width * factor).round();
    final int outputHeight = (height * factor).round();
    if (outputWidth <= width || outputHeight <= height) {
      return null;
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    ui.Image? intermediate;

    try {
      final List<ui.FragmentProgram> programs = await _ensurePrograms();

      final ui.Image bicubic = _runBicubic(programs[0], source, outputWidth, outputHeight);
      intermediate = bicubic;

      final ui.Image result = _runCas(programs[1], bicubic, outputWidth, outputHeight);

      /// `Picture.toImageSync` is lazy: the read-back is what guarantees both
      /// passes have actually been executed before the intermediate is freed.
      await result.toByteData(format: ui.ImageByteFormat.rawRgba);

      bicubic.dispose();
      intermediate = null;

      _cachePut(key, result, outputWidth * outputHeight * 4);

      stopwatch.stop();
      log.info('Upscale 2x: ${width}x$height -> ${outputWidth}x$outputHeight in ${stopwatch.elapsedMilliseconds}ms');

      return result;
    } catch (e, s) {
      log.error('Upscale failed: $e\n$s');
      return null;
    } finally {
      intermediate?.dispose();
    }
  }

  ui.Image _runBicubic(ui.FragmentProgram program, ui.Image source, int outputWidth, int outputHeight) {
    final ui.FragmentShader shader = program.fragmentShader();
    shader.setFloat(0, outputWidth.toDouble());
    shader.setFloat(1, outputHeight.toDouble());
    shader.setFloat(2, source.width.toDouble());
    shader.setFloat(3, source.height.toDouble());
    shader.setImageSampler(0, source);

    final ui.Image image = _draw(shader, outputWidth, outputHeight);
    shader.dispose();
    return image;
  }

  ui.Image _runCas(ui.FragmentProgram program, ui.Image source, int outputWidth, int outputHeight) {
    final ui.FragmentShader shader = program.fragmentShader();
    shader.setFloat(0, outputWidth.toDouble());
    shader.setFloat(1, outputHeight.toDouble());
    shader.setFloat(2, _sharpness);
    shader.setImageSampler(0, source);

    final ui.Image image = _draw(shader, outputWidth, outputHeight);
    shader.dispose();
    return image;
  }

  ui.Image _draw(ui.FragmentShader shader, int width, int height) {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..shader = shader,
    );

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = picture.toImageSync(width, height);

    picture.dispose();
    return image;
  }

  Future<List<ui.FragmentProgram>> _ensurePrograms() {
    return _programsFuture ??= () async {
      return <ui.FragmentProgram>[
        await ui.FragmentProgram.fromAsset(_bicubicShader),
        await ui.FragmentProgram.fromAsset(_casShader),
      ];
    }();
  }

  void _cachePut(String key, ui.Image image, int bytes) {
    _cache[key] = image;
    _cacheBytes += bytes;
    _touch(key);

    /// Evicted images are not disposed here: a widget may still be painting
    /// one. Dropping the reference is enough, the engine releases it once the
    /// last reference is gone.
    while (_cacheBytes > _maxCacheBytes && _lru.length > 1) {
      final String oldest = _lru.removeAt(0);
      final ui.Image? evicted = _cache.remove(oldest);
      if (evicted != null) {
        _cacheBytes -= evicted.width * evicted.height * 4;
      }
    }
  }

  void _touch(String key) {
    _lru.remove(key);
    _lru.add(key);
  }
}

final UpscaleService upscaleService = UpscaleService._();
