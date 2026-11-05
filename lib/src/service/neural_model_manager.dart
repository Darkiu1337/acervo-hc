import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:acervo_hc/src/model/neural_gpu.dart';
import 'package:acervo_hc/src/model/neural_upscale_config.dart';
import 'package:acervo_hc/src/network/eh_request.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/path_service.dart';
import 'package:acervo_hc/src/utils/archive_util.dart';

/// State of the managed Real-CUGAN install.
enum NeuralModelStatus { unknown, notAvailable, downloading, ready, error }

/// Paths of one usable Real-CUGAN install.
///
/// [rootDir] is the folder that contains `models-se` / `models-pro`;
/// [executableDir] is also the working directory used to start the binary, so
/// Windows finds `vcomp140.dll` next to it.
class NeuralModelPaths {
  final String binaryPath;
  final String rootDir;
  final String executableDir;

  const NeuralModelPaths({
    required this.binaryPath,
    required this.rootDir,
    required this.executableDir,
  });

  String modelsDir(NeuralUpscaleModel model) =>
      p.join(rootDir, model.directory);
}

/// Locates, downloads and extracts the Real-CUGAN ncnn package.
///
/// The package is large (~46 MB) and only needed on desktop. The service never
/// downloads silently: [ensureReady] is called from the settings page or from
/// an explicit "download" action.
class NeuralModelManager {
  NeuralModelManager._();

  static final NeuralModelManager instance = NeuralModelManager._();

  static const String _version = '20220728';
  static const String _releaseBase =
      'https://github.com/nihui/realcugan-ncnn-vulkan/releases/download/$_version';

  static const String _tinyPng =
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAACFSURBVHhe7dAhAQAADITA719681SAk0h2cmOwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2DWCwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2DWCwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2DWCwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2D0bQw7Koj1gSAAAAAElFTkSuQmCC';

  final ValueNotifier<NeuralModelStatus> status =
      ValueNotifier<NeuralModelStatus>(NeuralModelStatus.unknown);
  final ValueNotifier<double> downloadProgress = ValueNotifier<double>(0);
  final ValueNotifier<List<NeuralGpu>> gpus =
      ValueNotifier<List<NeuralGpu>>(const <NeuralGpu>[]);

  NeuralModelPaths? _paths;
  Future<void>? _initFuture;
  Future<bool>? _downloadFuture;
  bool _gpusLoaded = false;
  bool _gpusLoading = false;

  NeuralModelPaths? get paths => _paths;

  bool get isReady => status.value == NeuralModelStatus.ready && _paths != null;

  bool get isSupportedPlatform => Platform.isWindows || Platform.isLinux;

  String get _binaryName => Platform.isWindows
      ? 'realcugan-ncnn-vulkan.exe'
      : 'realcugan-ncnn-vulkan';

  String get _zipName => Platform.isWindows
      ? 'realcugan-ncnn-vulkan-$_version-windows.zip'
      : 'realcugan-ncnn-vulkan-$_version-ubuntu.zip';

  Directory get _managedRoot => Directory(
      p.join(pathService.getCacheDir().path, 'neural_models', _version));

  /// Looks for an existing install (bundled, managed or the one from the batch
  /// super-resolution feature) and marks the manager ready when it finds one.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    if (!isSupportedPlatform) {
      status.value = NeuralModelStatus.notAvailable;
      return;
    }

    try {
      final List<String> candidates = <String>[
        _managedRoot.path,
        p.join(p.dirname(Platform.resolvedExecutable), 'neural_models'),
        p.join(pathService.getVisibleDir().path, 'neural_models'),
      ];

      for (final String candidate in candidates) {
        final NeuralModelPaths? found = _locate(candidate);
        if (found != null) {
          _paths = found;
          status.value = NeuralModelStatus.ready;
          await _ensureExecutable(found.binaryPath);
          log.info('Neural upscaler ready: ${found.binaryPath}');
          return;
        }
      }
    } catch (e, s) {
      log.error('Neural upscaler init failed: $e\n$s');
      status.value = NeuralModelStatus.error;
      return;
    }

    status.value = NeuralModelStatus.notAvailable;
  }

  /// Downloads and extracts the package when it is not installed yet.
  Future<bool> ensureReady() async {
    await init();
    if (isReady) {
      return true;
    }
    if (!isSupportedPlatform) {
      status.value = NeuralModelStatus.notAvailable;
      return false;
    }

    final Future<bool>? inFlight = _downloadFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final Future<bool> future = _download();
    _downloadFuture = future;
    try {
      return await future;
    } finally {
      _downloadFuture = null;
    }
  }

  Future<bool> _download() async {
    final Directory root = _managedRoot;
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }

    final File zip = File(p.join(root.path, 'package.zip'));
    final Directory extract = Directory(p.join(root.path, 'package'));
    if (extract.existsSync()) {
      extract.deleteSync(recursive: true);
    }

    status.value = NeuralModelStatus.downloading;
    downloadProgress.value = 0;

    try {
      await ehRequest.download(
        url: '$_releaseBase/$_zipName',
        path: zip.path,
        receiveTimeout: 10 * 60 * 1000,
        onReceiveProgress: (int count, int total) {
          if (total > 0) {
            downloadProgress.value = (count / total).clamp(0.0, 1.0);
          }
        },
      );

      final bool extracted = await extractZipArchive(zip.path, extract.path);
      if (!extracted) {
        status.value = NeuralModelStatus.error;
        log.error('Neural upscaler: failed to extract ${zip.path}');
        return false;
      }

      try {
        zip.deleteSync();
      } catch (_) {}

      final NeuralModelPaths? found = _locate(extract.path);
      if (found == null) {
        status.value = NeuralModelStatus.error;
        log.error('Neural upscaler: package has no usable binary/models');
        return false;
      }

      await _ensureExecutable(found.binaryPath);
      _paths = found;
      _gpusLoaded = false;
      gpus.value = const <NeuralGpu>[];
      downloadProgress.value = 1;
      status.value = NeuralModelStatus.ready;
      log.info('Neural upscaler downloaded: ${found.binaryPath}');
      return true;
    } catch (e, s) {
      log.error('Neural upscaler download failed: $e\n$s');
      status.value = NeuralModelStatus.error;
      return false;
    }
  }

  /// Asks the ncnn binary to print its Vulkan devices once (a 64x64 dummy
  /// input is enough) and parses the `[index name]` lines. Cached for the app
  /// session; call with [force] to refresh after a model/GPU-driver change.
  Future<void> refreshGpus({bool force = false}) async {
    final NeuralModelPaths? paths = _paths;
    if (paths == null || _gpusLoading || (_gpusLoaded && !force)) {
      return;
    }
    _gpusLoading = true;
    final Directory temp = Directory(
      p.join(pathService.getCacheDir().path, 'neural_gpu'),
    );

    try {
      if (!temp.existsSync()) {
        temp.createSync(recursive: true);
      }
      final File input = File(p.join(temp.path, 'tiny.png'));
      final File output = File(p.join(temp.path, 'tiny_out.png'));
      await input.writeAsBytes(base64Decode(_tinyPng), flush: true);

      String modelDir = paths.modelsDir(NeuralUpscaleModel.se);
      if (!Directory(modelDir).existsSync()) {
        modelDir = paths.modelsDir(NeuralUpscaleModel.pro);
      }
      if (!Directory(modelDir).existsSync()) {
        return;
      }

      final Process process = await Process.start(
        paths.binaryPath,
        <String>[
          '-i',
          input.path,
          '-o',
          output.path,
          '-s',
          '2',
          '-n',
          '0',
          '-m',
          modelDir,
          '-v',
        ],
        workingDirectory: paths.executableDir,
        runInShell: false,
      );
      final Future<String> stderrFuture =
          process.stderr.transform(utf8.decoder).join();
      final Future<void> stdoutFuture = process.stdout.drain<void>();
      final int exitCode =
          await process.exitCode.timeout(const Duration(seconds: 15));
      final String stderr = await stderrFuture;
      await stdoutFuture;

      if (exitCode != 0) {
        log.warning('Neural GPU enumeration exited with $exitCode');
        return;
      }

      final List<NeuralGpu> list = parseNeuralGpus(stderr);
      gpus.value = list;
      _gpusLoaded = list.isNotEmpty;
      log.info(
        'Neural GPUs: ${list.map((NeuralGpu gpu) => '${gpu.index}=${gpu.name}').join(', ')}',
      );
    } catch (e, s) {
      log.warning('Neural GPU enumeration failed: $e\n$s');
    } finally {
      _gpusLoading = false;
      // Do not retry on every rebuild if the probe failed; the refresh button
      // forces a new attempt.
      _gpusLoaded = true;
      try {
        if (temp.existsSync()) {
          temp.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }

  NeuralModelPaths? _locate(String root) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) {
      return null;
    }

    try {
      for (final FileSystemEntity entity
          in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || p.basename(entity.path) != _binaryName) {
          continue;
        }
        final String executableDir = p.dirname(entity.path);
        if (!Directory(p.join(executableDir, 'models-se')).existsSync()) {
          continue;
        }
        return NeuralModelPaths(
          binaryPath: entity.path,
          rootDir: executableDir,
          executableDir: executableDir,
        );
      }
    } catch (e) {
      log.warning('Neural upscaler: cannot inspect $root: $e');
    }
    return null;
  }

  Future<void> _ensureExecutable(String path) async {
    if (!Platform.isLinux) {
      return;
    }
    try {
      await Process.run('chmod', <String>['+x', path]);
    } catch (e) {
      log.warning('Neural upscaler: chmod failed for $path: $e');
    }
  }
}

final NeuralModelManager neuralModelManager = NeuralModelManager.instance;
