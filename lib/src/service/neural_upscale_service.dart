import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:acervo_hc/src/model/neural_upscale_config.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/neural_model_manager.dart';
import 'package:acervo_hc/src/service/neural_queue.dart';
import 'package:acervo_hc/src/service/path_service.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';
import 'package:acervo_hc/src/utils/cover_hash_util.dart';

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

  /// Optional local file path (for downloaded galleries) to pass directly to
  /// `realcugan-ncnn-vulkan` without re-encoding a PNG on the raster thread.
  final String? sourcePath;

  /// Optional network URL (for online galleries) so the service can reuse the
  /// already-cached file from `extended_image` instead of PNG-encoding pixels.
  final String? sourceUrl;

  const NeuralRequest({
    required this.source,
    required this.cacheKey,
    this.index = 0,
    this.frameCount = 1,
    this.sourcePath,
    this.sourceUrl,
  });
}

/// Result returned to widgets. Callers own [image] (a cloned handle) and must
/// dispose it when replaced or unmounted.
class NeuralOutput {
  final ui.Image image;

  const NeuralOutput({
    required this.image,
  });
}

class _CachedNeuralEntry {
  final ui.Image image;
  final int bytes;

  const _CachedNeuralEntry({
    required this.image,
    required this.bytes,
  });
}

class _PreparedInput {
  final File file;
  final bool deleteWhenDone;

  const _PreparedInput(this.file, {required this.deleteWhenDone});
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
  final Completer<NeuralOutput?> completer = Completer<NeuralOutput?>();

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

  static const int _diskCacheBytes = 4 * 1024 * 1024 * 1024;

  /// Quiet time after a page change before pruning the queue and interrupting
  /// a job that fell outside the window. Without it, fast page turns would
  /// restart the GPU process on every frame.
  static const int _settleDelayMs = 250;

  /// Short breathing gap between consecutive background preload jobs (never
  /// applied to the visible focus page) so Vulkan command queues drain and the
  /// desktop compositor / Flutter UI never freeze during 5-page preloads.
  static const int _preloadBreatherMs = 150;

  /// Explicit tile size passed to `realcugan-ncnn-vulkan` (`-t`). Auto-tiling
  /// (`-t 0`) can submit huge single-dispatch Vulkan workloads on desktop GPUs
  /// that starve Windows DWM / trigger TDR freezes. `200` preserves identical
  /// quality (Real-CUGAN uses built-in tile overlap) while keeping each GPU
  /// chunk short and VRAM bounded.
  static const int _tileSize = 200;

  /// In `auto` mode only, skip already very high-resolution sources (>= 2400px
  /// wide). Explicit manual scales (2x/3x/4x) or gallery forced ON bypass this.
  static const int _autoSkipSourceWidth = 2400;

  final Map<String, _CachedNeuralEntry> _memory = <String, _CachedNeuralEntry>{};
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

  /// Bumped when model/scale/denoise/GPU/gallery-mode changes, so mounted
  /// widgets discard stale textures and re-request with the new settings.
  final ValueNotifier<int> configRevision = ValueNotifier<int>(0);

  bool _running = false;
  _NeuralJob? _runningJob;
  bool _abortRequested = false;
  bool _lastJobRanGpu = false;
  Timer? _settleTimer;
  int _generation = 0;
  int _writesSincePrune = 0;
  Process? _process;

  Future<void>? _initFuture;

  /// Scales memory cache budget with the configured preload window so all
  /// preloaded pages (e.g. 5 ahead + visible + 2 behind) stay hot in RAM
  /// instead of evicting page +1 before the user turns to it.
  int get _memoryCacheBudgetBytes {
    final int preload = readSetting.neuralUpscalePreload.value;
    final int slots = preload + 3;
    final int desired = slots * 72 * 1024 * 1024;
    return desired.clamp(256 * 1024 * 1024, 640 * 1024 * 1024);
  }

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

  /// Returns a cloned handle of the cached neural texture for [key], if still
  /// around. Caller owns the returned handle and must dispose it when done.
  NeuralOutput? cached(String key) {
    final _CachedNeuralEntry? entry = _memory[key];
    if (entry == null) {
      return null;
    }
    _touch(key);
    try {
      return NeuralOutput(image: entry.image.clone());
    } catch (_) {
      return null;
    }
  }

  /// Synchronous cache lookup for a decoded page, using the same key the
  /// request would compute. Lets a revisited page swap to the neural texture
  /// on its first frame instead of waiting for a queue round trip.
  NeuralOutput? cachedFor({
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
    for (final _CachedNeuralEntry entry in _memory.values) {
      try {
        entry.image.dispose();
      } catch (_) {}
    }
    _memory.clear();
    _lru.clear();
    _memoryBytes = 0;
  }

  /// Cancels queued work, drops the memory cache, and notifies mounted widgets
  /// to re-request under the new model/scale/denoise/gallery mode.
  void refreshSession() {
    cancelSession();
    clearMemoryCache();
    configRevision.value++;
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

  Future<NeuralOutput?> upscale(NeuralRequest request) async {
    await init();

    final int scale = _scaleFor(request.source.width, request.source.height);
    final String key = _keyFor(
      sourceKey: request.cacheKey,
      width: request.source.width,
      height: request.source.height,
      scale: scale,
    );
    final NeuralOutput? hit = cached(key);
    if (hit != null) {
      return hit;
    }

    if (!_shouldProcess(request, scale)) {
      return null;
    }

    final _NeuralJob? existing = _queued[key];
    if (existing != null) {
      final NeuralOutput? output = await existing.completer.future;
      return _cloneOutput(output);
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
    final NeuralOutput? output = await job.completer.future;
    return _cloneOutput(output);
  }

  static NeuralOutput? _cloneOutput(NeuralOutput? output) {
    if (output == null) {
      return null;
    }
    try {
      return NeuralOutput(image: output.image.clone());
    } catch (_) {
      return null;
    }
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

  void _finish(_NeuralJob job, NeuralOutput? output) {
    _queued.remove(job.key);
    if (!job.completer.isCompleted) {
      job.completer.complete(output);
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

    /// Only skip very wide sources when running purely in Auto scale mode.
    /// When the user picks a manual scale, honour their request as long as
    /// the texture budget allows it.
    final bool isAutoScale =
        readSetting.neuralUpscaleScale.value == NeuralUpscaleScale.auto;
    if (isAutoScale && request.source.width >= _autoSkipSourceWidth) {
      return false;
    }
    return neuralModelManager.isModelReady(readSetting.neuralUpscaleModel.value);
  }

  int get _denoise {
    final NeuralUpscaleModel model = readSetting.neuralUpscaleModel.value;
    if (!model.supportsDenoise) {
      return 0;
    }
    int value = readSetting.neuralUpscaleDenoise.value;
    if (model == NeuralUpscaleModel.pro && (value == 1 || value == 2)) {
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

        /// Give the GPU & desktop compositor a short breather between
        /// background preloads (never delay the visible focus page).
        if (_lastJobRanGpu && job.request.index != _queue.focus) {
          await Future<void>.delayed(
            const Duration(milliseconds: _preloadBreatherMs),
          );
          if (job.generation != _generation) {
            _finish(job, null);
            continue;
          }
          if (!inWindow(job.request.index)) {
            _finish(job, null);
            continue;
          }
        }

        _runningJob = job;
        _abortRequested = false;
        _lastJobRanGpu = false;
        try {
          final NeuralOutput? output = await _run(job);
          log.info(
            'Neural upscale: page ${job.request.index} ready '
            '(queue=${_jobs.length}, waited=${job.queued.elapsedMilliseconds}ms)',
          );
          _finish(job, output);
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

  Future<NeuralOutput?> _run(_NeuralJob job) async {
    final _CachedNeuralEntry? memoryHit = _memory[job.key];
    if (memoryHit != null) {
      _touch(job.key);
      return NeuralOutput(image: memoryHit.image);
    }
    if (_abortRequested) {
      throw const _NeuralAborted();
    }

    final File output = File(p.join(_cacheDir.path, '${job.key}.png'));
    if (await output.exists() && (await output.length()) > 0) {
      final ui.Image? decoded = await _decode(output);
      if (decoded != null) {
        _memoryPut(job.key, decoded);
        return NeuralOutput(image: decoded);
      }
      // A partial/corrupt file from an interrupted run: drop it so the next
      // request retries the process.
      try {
        await output.delete();
      } catch (_) {}
    }

    final NeuralUpscaleModel model = readSetting.neuralUpscaleModel.value;
    final NeuralModelPaths? paths = neuralModelManager.pathsFor(model);
    if (paths == null) {
      return null;
    }
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

    final _PreparedInput? prepared = await _prepareInputFile(job.request, tmpDir);
    if (prepared == null) {
      return null;
    }

    try {
      _lastJobRanGpu = true;
      final bool ok =
          await _runProcess(prepared.file, output, paths, model, modelDir, scale);
      if (_abortRequested) {
        try {
          if (await output.exists()) {
            await output.delete();
          }
        } catch (_) {}
        throw const _NeuralAborted();
      }
      if (!ok) {
        return null;
      }

      final ui.Image? decoded = await _decode(output);
      if (decoded != null) {
        _memoryPut(job.key, decoded);
        if (++_writesSincePrune >= 8) {
          _writesSincePrune = 0;
          unawaited(_pruneDisk());
        }
        return NeuralOutput(image: decoded);
      } else {
        try {
          await output.delete();
        } catch (_) {}
      }
      return null;
    } finally {
      if (prepared.deleteWhenDone) {
        try {
          if (await prepared.file.exists()) {
            await prepared.file.delete();
          }
        } catch (_) {}
      }
    }
  }

  /// Avoids the expensive raster-thread `source.toByteData(png)` stall whenever
  /// the original JPG/PNG/WebP file is already on disk (local download or
  /// `extended_image` disk cache).
  Future<_PreparedInput?> _prepareInputFile(
    NeuralRequest request,
    Directory tmpDir,
  ) async {
    final bool canUseDiskOriginal = !readSetting.enableMaxImageKilobyte.value;

    if (canUseDiskOriginal && request.sourcePath != null && request.sourcePath!.isNotEmpty) {
      final File localFile = File(request.sourcePath!);
      if (await localFile.exists()) {
        final String? ext = await _detectSupportedImageExt(localFile);
        if (ext != null) {
          final String lowerPath = localFile.path.toLowerCase();
          if (lowerPath.endsWith('.$ext') || (ext == 'jpg' && lowerPath.endsWith('.jpeg'))) {
            return _PreparedInput(localFile, deleteWhenDone: false);
          }
          final File copy = File(
            p.join(tmpDir.path, '${DateTime.now().microsecondsSinceEpoch}.$ext'),
          );
          await localFile.copy(copy.path);
          return _PreparedInput(copy, deleteWhenDone: true);
        }
      }
    }

    if (canUseDiskOriginal && request.sourceUrl != null && request.sourceUrl!.isNotEmpty) {
      try {
        final String normalizedUrl = CoverHashUtil.normalizeCoverUrl(request.sourceUrl!);
        final File? cachedFile = await getCachedImageFile(normalizedUrl);
        if (cachedFile != null && await cachedFile.exists()) {
          final String? ext = await _detectSupportedImageExt(cachedFile);
          if (ext != null) {
            final File copy = File(
              p.join(tmpDir.path, '${DateTime.now().microsecondsSinceEpoch}.$ext'),
            );
            await cachedFile.copy(copy.path);
            return _PreparedInput(copy, deleteWhenDone: true);
          }
        }
      } catch (_) {
        // Fall through to PNG encode fallback.
      }
    }

    /// Fallback: encode the decoded image to a temporary PNG (no fsync).
    final ui.Image source = request.source.clone();
    try {
      final ByteData? data = await source.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        return null;
      }
      final File tempPng = File(
        p.join(tmpDir.path, '${DateTime.now().microsecondsSinceEpoch}.png'),
      );
      await tempPng.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: false,
      );
      return _PreparedInput(tempPng, deleteWhenDone: true);
    } finally {
      source.dispose();
    }
  }

  /// Detects JPEG, PNG, or WebP from the first 12 bytes (`realcugan-ncnn-vulkan`
  /// decodes all three natively). Returns `null` for unsupported formats.
  static Future<String?> _detectSupportedImageExt(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final Uint8List header = await raf.read(12);
      if (header.length < 4) {
        return null;
      }
      // JPEG: FF D8 FF
      if (header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF) {
        return 'jpg';
      }
      // PNG: 89 50 4E 47
      if (header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47) {
        return 'png';
      }
      // WebP: RIFF....WEBP
      if (header.length >= 12 &&
          header[0] == 0x52 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x46 &&
          header[8] == 0x57 &&
          header[9] == 0x45 &&
          header[10] == 0x42 &&
          header[11] == 0x50) {
        return 'webp';
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  Future<bool> _runProcess(
    File input,
    File output,
    NeuralModelPaths paths,
    NeuralUpscaleModel model,
    String modelDir,
    int scale,
  ) async {
    if (await output.exists()) {
      try {
        await output.delete();
      } catch (_) {}
    }

    final List<String> args = buildNeuralProcessArgs(
      model: model,
      inputPath: input.path,
      outputPath: output.path,
      modelDir: modelDir,
      scale: scale,
      denoise: _denoise,
      gpuId: readSetting.neuralUpscaleGpuId.value,
      tileSize: _tileSize,
    );

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
          log.error(
            'Neural upscale (${model.name}) exited with $exitCode: $stderr',
          );
        }
        return false;
      }
      if (!await output.exists() || await output.length() == 0) {
        log.error('Neural upscale (${model.name}) produced no output');
        return false;
      }

      log.info(
        'Neural upscale: ${input.path} -> ${output.path} in ${stopwatch.elapsedMilliseconds}ms '
        '(model=${model.name}, scale=$scale, denoise=$_denoise, tile=$_tileSize)',
      );
      return true;
    } on TimeoutException {
      _process?.kill();
      _process = null;
      log.error('Neural upscale (${model.name}) timed out');
      return false;
    } catch (e, s) {
      _process = null;
      log.error('Neural upscale (${model.name}) failed: $e\n$s');
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

  void _memoryPut(String key, ui.Image image) {
    final int bytes = image.width * image.height * 4;
    final _CachedNeuralEntry? old = _memory[key];
    if (old != null) {
      _memoryBytes -= old.bytes;
      try {
        old.image.dispose();
      } catch (_) {}
    }
    _memory[key] = _CachedNeuralEntry(image: image, bytes: bytes);
    _memoryBytes += bytes;
    _touch(key);

    final int budget = _memoryCacheBudgetBytes;
    while (_memoryBytes > budget && _lru.length > 1) {
      final String oldest = _lru.removeAt(0);
      final _CachedNeuralEntry? evicted = _memory.remove(oldest);
      if (evicted != null) {
        _memoryBytes -= evicted.bytes;
        try {
          evicted.image.dispose();
        } catch (_) {}
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
      final List<File> files = <File>[];
      await for (final FileSystemEntity entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.png')) {
          files.add(entity);
        }
      }
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
