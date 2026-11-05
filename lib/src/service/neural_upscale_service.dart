import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import 'package:acervo_hc/src/model/neural_upscale_config.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/neural_model_manager.dart';
import 'package:acervo_hc/src/service/path_service.dart';
import 'package:acervo_hc/src/service/super_resolution_service.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';
import 'package:acervo_hc/src/setting/super_resolution_setting.dart';

/// One page to be enhanced by the neural upscaler.
class NeuralRequest {
  /// Decoded page image. The caller keeps ownership and must dispose its own
  /// clone when the future completes.
  final ui.Image source;

  /// Stable source identity: image hash, local path or URL.
  final String cacheKey;

  /// Visible page requests jump ahead of prefetched neighbours.
  final bool priority;

  /// Decoded frame count. Multi-frame images (GIF/animated WebP) are skipped.
  final int frameCount;

  /// Optional local file, used to avoid re-encoding the decoded bitmap.
  final String? sourcePath;

  const NeuralRequest({
    required this.source,
    required this.cacheKey,
    this.priority = false,
    this.frameCount = 1,
    this.sourcePath,
  });
}

class _NeuralJob {
  final NeuralRequest request;
  final String key;
  final int generation;
  final Completer<ui.Image?> completer = Completer<ui.Image?>();

  _NeuralJob(this.request, this.key, this.generation);
}

/// Runs `realcugan-ncnn-vulkan` on demand for the visible page and its
/// neighbours, with an in-memory LRU and a persistent disk cache.
class NeuralUpscaleService {
  NeuralUpscaleService._();

  static final NeuralUpscaleService instance = NeuralUpscaleService._();

  static const int _memoryCacheBytes = 192 * 1024 * 1024;
  static const int _diskCacheBytes = 2 * 1024 * 1024 * 1024;
  static const int _maxOutputDimension = neuralMaxOutputDimension;

  /// Sources at or above this width already look fine with the shader.
  static const int _skipSourceWidth = 1800;

  final Map<String, ui.Image> _memory = <String, ui.Image>{};
  final List<String> _lru = <String>[];
  int _memoryBytes = 0;

  final Map<String, Future<ui.Image?>> _pending = <String, Future<ui.Image?>>{};
  final List<_NeuralJob> _jobs = <_NeuralJob>[];
  bool _running = false;
  int _generation = 0;
  int _writesSincePrune = 0;
  Process? _process;

  Future<void>? _initFuture;

  Directory get _cacheDir {
    final Directory dir =
        Directory(p.join(pathService.getCacheDir().path, 'neural_upscale'));
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

  void clearMemoryCache() {
    _memory.clear();
    _lru.clear();
    _memoryBytes = 0;
  }

  /// Cancels queued work and kills the current process. The disk cache stays.
  void cancelSession() {
    _generation++;
    try {
      _process?.kill();
    } catch (_) {}
    _process = null;

    final List<_NeuralJob> jobs = List<_NeuralJob>.from(_jobs);
    _jobs.clear();
    for (final _NeuralJob job in jobs) {
      if (!job.completer.isCompleted) {
        job.completer.complete(null);
      }
    }
  }

  Future<ui.Image?> upscale(NeuralRequest request) async {
    await init();

    final int scale =
        neuralScaleFor(request.source.width, request.source.height);
    final String key = neuralCacheKey(
      sourceKey: request.cacheKey,
      model: readSetting.neuralUpscaleModel.value,
      denoise: _denoise,
      scale: scale,
      width: request.source.width,
      height: request.source.height,
    );
    final ui.Image? hit = cached(key);
    if (hit != null) {
      return hit;
    }

    if (!_shouldProcess(request, scale)) {
      return null;
    }

    final Future<ui.Image?>? pending = _pending[key];
    if (pending != null) {
      return pending;
    }

    final _NeuralJob job = _NeuralJob(request, key, _generation);
    final Future<ui.Image?> future = job.completer.future;
    _pending[key] = future;
    if (request.priority) {
      _jobs.insert(0, job);
    } else {
      _jobs.add(job);
    }
    unawaited(_pump());
    return future.whenComplete(() => _pending.remove(key));
  }

  bool _shouldProcess(NeuralRequest request, int scale) {
    if (!readSetting.enableNeuralUpscale.value) {
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

  bool get _batchActive {
    try {
      return superResolutionService.superResolutionInfoTable
          .entries()
          .any((entry) => entry.value.status == SuperResolutionStatus.running);
    } catch (_) {
      return false;
    }
  }

  Future<void> _pump() async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      while (_jobs.isNotEmpty) {
        final _NeuralJob job = _jobs.removeAt(0);
        if (job.generation != _generation) {
          if (!job.completer.isCompleted) {
            job.completer.complete(null);
          }
          continue;
        }
        try {
          final ui.Image? image = await _run(job);
          if (!job.completer.isCompleted) {
            job.completer.complete(image);
          }
        } catch (e, s) {
          log.error('Neural upscale failed: $e\n$s');
          if (!job.completer.isCompleted) {
            job.completer.complete(null);
          }
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

    final File output = File(p.join(_cacheDir.path, '${job.key}.png'));
    if (output.existsSync() && output.lengthSync() > 0) {
      final ui.Image? decoded = await _decode(output);
      if (decoded != null) {
        _memoryPut(job.key, decoded);
        return decoded;
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
    if (_batchActive) {
      log.info('Neural upscale skipped: batch super resolution is running');
      return null;
    }

    final NeuralModelPaths paths = neuralModelManager.paths!;
    final NeuralUpscaleModel model = readSetting.neuralUpscaleModel.value;
    final String modelDir = paths.modelsDir(model);
    if (!Directory(modelDir).existsSync()) {
      log.warning('Neural upscale: missing model directory $modelDir');
      return null;
    }

    final int scale =
        neuralScaleFor(job.request.source.width, job.request.source.height);
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
      '${superResolutionSetting.gpuId.value}',
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
        log.error('Neural upscale process exited with $exitCode: $stderr');
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
