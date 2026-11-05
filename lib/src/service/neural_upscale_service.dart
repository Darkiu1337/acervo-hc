import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:acervo_hc/src/model/neural_pixels.dart';
import 'package:acervo_hc/src/model/neural_upscale_config.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/neural_model_manager.dart';
import 'package:acervo_hc/src/service/neural_queue.dart';
import 'package:acervo_hc/src/service/path_service.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';

/// One page to be enhanced by the neural upscaler.
class NeuralRequest {
  /// Decoded page image. The caller keeps ownership and must dispose its own
  /// clone when the future completes.
  final ui.Image source;

  /// Stable source identity: image hash, local path or URL.
  final String cacheKey;

  /// Absolute page index. The service keeps the queue sorted around the page
  /// the reader is showing, so the visible page always runs first.
  final int index;

  /// Decoded frame count. Multi-frame images (GIF/animated WebP) are skipped.
  final int frameCount;

  /// Optional local file, used to avoid re-encoding the decoded bitmap.
  final String? sourcePath;

  const NeuralRequest({
    required this.source,
    required this.cacheKey,
    this.index = 0,
    this.frameCount = 1,
    this.sourcePath,
  });
}

/// The job was interrupted on purpose (focus moved away or the session was
/// closed); it is requeued instead of being reported as a failure.
class _NeuralAborted implements Exception {
  const _NeuralAborted();
}

class _NeuralJob {
  final NeuralRequest request;
  final String key;
  final int generation;
  final Completer<ui.Image?> completer = Completer<ui.Image?>();

  /// Starts when the page asks for the neural pass, so the log reports the
  /// time the user actually waited (queue included).
  final Stopwatch queued = Stopwatch()..start();

  _NeuralJob(this.request, this.key, this.generation);
}

/// Runs `realcugan-ncnn-vulkan` on demand for the visible page and its
/// neighbours, with an in-memory LRU and a persistent disk cache.
class NeuralUpscaleService {
  NeuralUpscaleService._();

  static final NeuralUpscaleService instance = NeuralUpscaleService._();

  static const int _memoryCacheBytes = 192 * 1024 * 1024;
  static const int _diskCacheBytes = 4 * 1024 * 1024 * 1024;
  static const int _maxOutputDimension = neuralMaxOutputDimension;

  /// Quiet time after a page change before pruning the queue and interrupting
  /// a job that fell outside the window. Without it, fast page turns would
  /// restart the GPU process on every frame.
  static const int _settleDelayMs = 250;

  /// Sources at or above this width already look fine with the shader.
  static const int _skipSourceWidth = 1800;

  final Map<String, ui.Image> _memory = <String, ui.Image>{};
  final List<String> _lru = <String>[];
  int _memoryBytes = 0;

  /// Every job that is queued or running, by computed cache key. Used to
  /// deduplicate requests and to keep the widget attached to the waiting job.
  final Map<String, _NeuralJob> _queued = <String, _NeuralJob>{};
  final List<_NeuralJob> _jobs = <_NeuralJob>[];
  final NeuralQueue _queue = NeuralQueue();

  /// Index of the page the reader is showing. Widgets listen to it to know
  /// whether they are inside the preload window.
  final ValueNotifier<int> focusIndex = ValueNotifier<int>(0);

  /// Bumped when the configured window changes, so mounted pages re-check
  /// whether they are inside it.
  final ValueNotifier<int> windowRevision = ValueNotifier<int>(0);

  bool _running = false;
  _NeuralJob? _runningJob;
  bool _abortRequested = false;
  Timer? _settleTimer;
  int _generation = 0;
  int _writesSincePrune = 0;
  Process? _process;

  Future<void>? _initFuture;

  Directory get _cacheDirPath =>
      Directory(p.join(pathService.getCacheDir().path, 'neural_upscale'));

  Directory get _cacheDir {
    final Directory dir = _cacheDirPath;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    await neuralModelManager.init();
    unawaited(_pruneDisk());
  }

  /// Returns the cached neural texture for [key], if still around.
  ui.Image? cached(String key) {
    final ui.Image? image = _memory[key];
    if (image == null) {
      return null;
    }
    _touch(key);
    return image;
  }

  /// Synchronous cache lookup for a decoded page, using the same key the
  /// request would compute. Lets a revisited page swap to the neural texture
  /// on its first frame instead of waiting for a queue round trip.
  ui.Image? cachedFor({
    required String sourceKey,
    required int width,
    required int height,
  }) {
    final int scale = _scaleFor(width, height);
    if (scale < 2) {
      return null;
    }
    return cached(_keyFor(
      sourceKey: sourceKey,
      width: width,
      height: height,
      scale: scale,
    ));
  }

  /// Whether [index] is inside the preload window around the visible page.
  bool inWindow(int index) {
    _syncQueue();
    return _queue.contains(index);
  }

  /// Tells the service which page is on screen. Called by the reader on every
  /// page change and on jumps.
  void setFocus(int index) {
    _syncQueue();
    if (_queue.focus == index) {
      return;
    }
    _queue.setFocus(index);
    focusIndex.value = index;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: _settleDelayMs), _settle);
  }

  void clearMemoryCache() {
    _memory.clear();
    _lru.clear();
    _memoryBytes = 0;
  }

  /// Cancels queued work and kills the current process. The disk cache stays.
  void cancelSession() {
    _generation++;
    _abortRequested = true;
    _settleTimer?.cancel();
    _settleTimer = null;
    try {
      _process?.kill();
    } catch (_) {}
    _process = null;

    final List<_NeuralJob> jobs = List<_NeuralJob>.from(_jobs);
    _jobs.clear();
    for (final _NeuralJob job in jobs) {
      _finish(job, null);
    }
    final _NeuralJob? running = _runningJob;
    if (running != null) {
      _finish(running, null);
    }
  }

  /// Deletes every cached neural page, keeping the downloaded model.
  ///
  /// Called when the app exits (and once on startup, as a safety net for
  /// crashes) so the multi-gigabyte cache never survives a full shutdown.
  Future<void> clearDiskCache() async {
    final Directory dir = _cacheDirPath;
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        log.info('Neural upscale: disk cache cleared (${dir.path})');
      }
    } catch (e) {
      log.warning('Neural upscale: clear disk cache failed: $e');
    }
  }

  Future<ui.Image?> upscale(NeuralRequest request) async {
    await init();

    final int scale = _scaleFor(request.source.width, request.source.height);
    final String key = _keyFor(
      sourceKey: request.cacheKey,
      width: request.source.width,
      height: request.source.height,
      scale: scale,
    );
    final ui.Image? hit = cached(key);
    if (hit != null) {
      return hit;
    }

    if (!_shouldProcess(request, scale)) {
      return null;
    }

    final _NeuralJob? existing = _queued[key];
    if (existing != null) {
      return existing.completer.future;
    }

    /// Outside the window the GPU would only waste time. The widget asks again
    /// when the page comes back into range.
    if (!inWindow(request.index)) {
      return null;
    }

    final _NeuralJob job = _NeuralJob(request, key, _generation);
    _queued[key] = job;
    _jobs.add(job);
    unawaited(_pump());
    return job.completer.future;
  }

  int _scaleFor(int width, int height) => neuralScaleFor(
        width,
        height,
        readSetting.neuralUpscaleScale.value,
        readSetting.neuralUpscaleModel.value.maxScale,
      );

  String _keyFor({
    required String sourceKey,
    required int width,
    required int height,
    required int scale,
  }) =>
      neuralCacheKey(
        sourceKey: sourceKey,
        model: readSetting.neuralUpscaleModel.value,
        denoise: _denoise,
        scale: scale,
        width: width,
        height: height,
      );

  void _syncQueue() {
    _queue.setAhead(readSetting.neuralUpscalePreload.value);
  }

  /// Drops the pages that left the window and interrupts the running job when
  /// it is blocking the visible page or when it is no longer worth finishing.
  /// Reapplies the configured window after the user changes it while reading.
  void refreshWindow() {
    _settleTimer?.cancel();
    _settleTimer = null;
    windowRevision.value++;
    _settle();
  }

  void _settle() {
    _pruneQueue();
    final _NeuralJob? running = _runningJob;
    if (running == null) {
      return;
    }
    final bool focusPending =
        _jobs.any((_NeuralJob job) => job.request.index == _queue.focus);
    if (focusPending && running.request.index != _queue.focus) {
      _abortCurrent();
      return;
    }
    if (!inWindow(running.request.index)) {
      _abortCurrent();
    }
  }

  void _abortCurrent() {
    _abortRequested = true;
    try {
      _process?.kill();
    } catch (_) {}
  }

  void _pruneQueue() {
    _syncQueue();
    if (_jobs.isEmpty) {
      return;
    }
    final List<int> indexes =
        _jobs.map((_NeuralJob job) => job.request.index).toList();
    final List<int> stale = _queue.stale(indexes);
    for (int i = stale.length - 1; i >= 0; i--) {
      final _NeuralJob job = _jobs.removeAt(stale[i]);
      _finish(job, null);
    }
  }

  _NeuralJob? _takeNext() {
    if (_jobs.isEmpty) {
      return null;
    }
    _syncQueue();
    final int position = _queue.pick(
      _jobs.map((_NeuralJob job) => job.request.index).toList(),
    );
    if (position < 0) {
      return null;
    }
    return _jobs.removeAt(position);
  }

  void _finish(_NeuralJob job, ui.Image? image) {
    _queued.remove(job.key);
    if (!job.completer.isCompleted) {
      job.completer.complete(image);
    }
  }

  bool _shouldProcess(NeuralRequest request, int scale) {
    if (!readSetting.enableNeuralUpscale.value) {
      return false;
    }
    if (scale < 2) {
      return false;
    }
    if (request.frameCount > 1) {
      return false;
    }
    if (request.source.width <= 0 || request.source.height <= 0) {
      return false;
    }
    if (request.source.width >= _skipSourceWidth) {
      return false;
    }
    if (request.source.width * scale > _maxOutputDimension ||
        request.source.height * scale > _maxOutputDimension) {
      return false;
    }
    return neuralModelManager.isReady;
  }

  int get _denoise {
    int value = readSetting.neuralUpscaleDenoise.value;
    if (readSetting.neuralUpscaleModel.value == NeuralUpscaleModel.pro &&
        (value == 1 || value == 2)) {
      value = 0;
    }
    if (value < -1) {
      return -1;
    }
    if (value > 3) {
      return 3;
    }
    return value;
  }

  Future<void> _pump() async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      while (true) {
        _pruneQueue();
        final _NeuralJob? job = _takeNext();
        if (job == null) {
          break;
        }
        if (job.generation != _generation) {
          _finish(job, null);
          continue;
        }

        _runningJob = job;
        _abortRequested = false;
        try {
          final ui.Image? image = await _run(job);
          log.info(
            'Neural upscale: page ${job.request.index} ready '
            '(queue=${_jobs.length}, waited=${job.queued.elapsedMilliseconds}ms)',
          );
          _finish(job, image);
        } on _NeuralAborted {
          /// The page left the window while it was running. Keep the job
          /// queued so the widget keeps waiting instead of falling back
          /// forever; the pump picks the visible page next.
          if (job.generation == _generation) {
            _jobs.add(job);
          } else {
            _finish(job, null);
          }
        } catch (e, s) {
          log.error('Neural upscale failed: $e\n$s');
          _finish(job, null);
        } finally {
          _runningJob = null;
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<ui.Image?> _run(_NeuralJob job) async {
    final ui.Image? memoryHit = cached(job.key);
    if (memoryHit != null) {
      return memoryHit;
    }
    if (_abortRequested) {
      throw const _NeuralAborted();
    }

    final bool grayscale = await _isGrayscaleSource(job.request.source);
    if (_abortRequested) {
      throw const _NeuralAborted();
    }

    final File output = File(p.join(_cacheDir.path, '${job.key}.png'));
    if (output.existsSync() && output.lengthSync() > 0) {
      final ui.Image? decoded = await _decode(output);
      if (decoded != null) {
        final ui.Image normalized = grayscale
            ? (await _desaturate(decoded, output)) ?? decoded
            : decoded;
        if (normalized != decoded) {
          decoded.dispose();
        }
        _memoryPut(job.key, normalized);
        return normalized;
      }
      // A partial/corrupt file from an interrupted run: drop it so the next
      // request retries the process.
      try {
        output.deleteSync();
      } catch (_) {}
    }

    if (!neuralModelManager.isReady) {
      return null;
    }
    final NeuralModelPaths paths = neuralModelManager.paths!;
    final NeuralUpscaleModel model = readSetting.neuralUpscaleModel.value;
    final String modelDir = paths.modelsDir(model);
    if (!Directory(modelDir).existsSync()) {
      log.warning('Neural upscale: missing model directory $modelDir');
      return null;
    }

    final int scale = _scaleFor(
      job.request.source.width,
      job.request.source.height,
    );
    final Directory tmpDir = Directory(p.join(_cacheDir.path, 'tmp'));
    if (!tmpDir.existsSync()) {
      tmpDir.createSync(recursive: true);
    }
    final File input = File(
        p.join(tmpDir.path, '${DateTime.now().microsecondsSinceEpoch}.png'));

    final ui.Image source = job.request.source.clone();
    try {
      final ByteData? data =
          await source.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        return null;
      }
      await input.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true);

      final bool ok = await _runProcess(input, output, paths, modelDir, scale);
      if (_abortRequested) {
        try {
          if (output.existsSync()) {
            output.deleteSync();
          }
        } catch (_) {}
        throw const _NeuralAborted();
      }
      if (!ok) {
        return null;
      }

      ui.Image? decoded = await _decode(output);
      if (decoded != null) {
        if (grayscale) {
          final ui.Image? gray = await _desaturate(decoded, output);
          if (gray != null && gray != decoded) {
            decoded.dispose();
            decoded = gray;
          }
        }
        _memoryPut(job.key, decoded);
        if (++_writesSincePrune >= 8) {
          _writesSincePrune = 0;
          unawaited(_pruneDisk());
        }
      } else {
        try {
          output.deleteSync();
        } catch (_) {}
      }
      return decoded;
    } finally {
      source.dispose();
      try {
        if (input.existsSync()) {
          input.deleteSync();
        }
      } catch (_) {}
    }
  }

  Future<bool> _runProcess(File input, File output, NeuralModelPaths paths,
      String modelDir, int scale) async {
    if (output.existsSync()) {
      try {
        output.deleteSync();
      } catch (_) {}
    }

    final List<String> args = <String>[
      '-i',
      input.path,
      '-o',
      output.path,
      '-s',
      '$scale',
      '-n',
      '$_denoise',
      '-m',
      modelDir,
      '-g',
      '${readSetting.neuralUpscaleGpuId.value}',
      '-f',
      'png',
      '-t',
      '0',
    ];

    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final Process process = await Process.start(
        paths.binaryPath,
        args,
        workingDirectory: paths.executableDir,
        runInShell: false,
      );
      _process = process;
      if (_abortRequested) {
        try {
          process.kill();
        } catch (_) {}
      }

      final Future<String> stderrFuture =
          process.stderr.transform(utf8.decoder).join();
      final Future<void> stdoutFuture = process.stdout.drain<void>();
      final int exitCode =
          await process.exitCode.timeout(const Duration(seconds: 60));
      final String stderr = await stderrFuture;
      await stdoutFuture;
      _process = null;
      stopwatch.stop();

      if (exitCode != 0) {
        if (_abortRequested) {
          log.info('Neural upscale: interrupted (focus moved)');
        } else {
          log.error('Neural upscale process exited with $exitCode: $stderr');
        }
        return false;
      }
      if (!output.existsSync() || output.lengthSync() == 0) {
        log.error('Neural upscale process produced no output');
        return false;
      }

      log.info(
        'Neural upscale: ${input.path} -> ${output.path} in ${stopwatch.elapsedMilliseconds}ms (scale=$scale, denoise=$_denoise)',
      );
      return true;
    } on TimeoutException {
      _process?.kill();
      _process = null;
      log.error('Neural upscale process timed out');
      return false;
    } catch (e, s) {
      _process = null;
      log.error('Neural upscale process failed: $e\n$s');
      return false;
    }
  }

  Future<ui.Image?> _decode(File file) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (e, s) {
      log.error('Neural upscale: cannot decode ${file.path}: $e\n$s');
      return null;
    }
  }

  Future<bool> _isGrayscaleSource(ui.Image source) async {
    try {
      final ByteData? data =
          await source.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        return false;
      }
      return isGrayscaleRgba(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      return false;
    }
  }

  Future<ui.Image?> _desaturate(ui.Image image, File output) async {
    try {
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        return null;
      }
      final Uint8List raw =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      // Already neutral (e.g. a v2 cache hit): keep the decoded image and
      // avoid rewriting the file.
      if (isGrayscaleRgba(raw, saturatedDelta: 3, maxColoredRatio: 0.001)) {
        return image;
      }
      final Uint8List rgba = desaturateRgba(raw);
      final ui.Image gray =
          await _imageFromPixels(rgba, image.width, image.height);
      final ByteData? png =
          await gray.toByteData(format: ui.ImageByteFormat.png);
      if (png != null) {
        await output.writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          flush: true,
        );
      }
      return gray;
    } catch (e, s) {
      log.warning('Neural upscale: desaturate failed: $e\n$s');
      return null;
    }
  }

  Future<ui.Image> _imageFromPixels(Uint8List rgba, int width, int height) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  void _memoryPut(String key, ui.Image image) {
    final int bytes = image.width * image.height * 4;
    final ui.Image? old = _memory[key];
    if (old != null) {
      _memoryBytes -= old.width * old.height * 4;
    }
    _memory[key] = image;
    _memoryBytes += bytes;
    _touch(key);

    // Evicted textures are not disposed here: a widget may still be painting
    // one. Dropping the reference is enough; the engine releases it when the
    // last reference is gone.
    while (_memoryBytes > _memoryCacheBytes && _lru.length > 1) {
      final String oldest = _lru.removeAt(0);
      final ui.Image? evicted = _memory.remove(oldest);
      if (evicted != null) {
        _memoryBytes -= evicted.width * evicted.height * 4;
      }
    }
  }

  void _touch(String key) {
    _lru.remove(key);
    _lru.add(key);
  }

  Future<void> _pruneDisk() async {
    try {
      final Directory dir = _cacheDir;
      final List<File> files = dir
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('.png'))
          .toList();
      if (files.isEmpty) {
        return;
      }

      final List<MapEntry<File, FileStat>> entries =
          <MapEntry<File, FileStat>>[];
      for (final File file in files) {
        entries.add(MapEntry<File, FileStat>(file, await file.stat()));
      }
      entries.sort((MapEntry<File, FileStat> a, MapEntry<File, FileStat> b) =>
          a.value.modified.compareTo(b.value.modified));

      int total = entries.fold(0,
          (int sum, MapEntry<File, FileStat> entry) => sum + entry.value.size);
      for (final MapEntry<File, FileStat> entry in entries) {
        if (total <= _diskCacheBytes) {
          break;
        }
        try {
          await entry.key.delete();
          total -= entry.value.size;
        } catch (_) {}
      }
    } catch (e) {
      log.warning('Neural upscale: disk cache prune failed: $e');
    }
  }
}

final NeuralUpscaleService neuralUpscaleService = NeuralUpscaleService.instance;
