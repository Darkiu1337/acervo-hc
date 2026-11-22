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

/// State of a managed neural upscaler install.
enum NeuralModelStatus { unknown, notAvailable, downloading, ready, error }

/// Paths of one usable neural upscaler install.
///
/// [rootDir] is the folder that contains each model's subfolder;
/// [executableDir] is also the working directory used to start the binary, so
/// Windows finds `vcomp140.dll` next to it when needed.
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

/// Locates, downloads and extracts managed NCNN upscaler binaries and weights
/// (`realcugan-ncnn-vulkan` and `upscayl-bin` + SPAN / Compact / Real-ESRGAN).
///
/// Downloads are only triggered explicitly via [ensureModelReady] /
/// [ensureReady] from settings or an explicit user action.
class NeuralModelManager {
  NeuralModelManager._();

  static final NeuralModelManager instance = NeuralModelManager._();

  static const String _realcuganVersion = '20220728';
  static const String _realcuganReleaseBase =
      'https://github.com/nihui/realcugan-ncnn-vulkan/releases/download/$_realcuganVersion';

  static const String _upscaylVersion = '20251207-174704';
  static const String _upscaylReleaseBase =
      'https://github.com/upscayl/upscayl-ncnn/releases/download/$_upscaylVersion';

  static const String _rveModelsBase =
      'https://github.com/TNTwise/real-video-enhancer-models/releases/download/models';
  static const String _phhofmHfa2kBase =
      'https://github.com/Phhofm/models/releases/download/2xHFA2k_compact_multijpg';

  static const String _tinyPng =
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAACFSURBVHhe7dAhAQAADITA719681SAk0h2cmOwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2DWCwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2DWCwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2DWCwaQCDTQMYbBrAYNMABpsGMNg0gMGmAQw2D0bQw7Koj1gSAAAAAElFTkSuQmCC';

  final ValueNotifier<NeuralModelStatus> status =
      ValueNotifier<NeuralModelStatus>(NeuralModelStatus.unknown);
  final ValueNotifier<NeuralUpscaleModel?> downloadingModel =
      ValueNotifier<NeuralUpscaleModel?>(null);
  final ValueNotifier<double> downloadProgress = ValueNotifier<double>(0);
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final ValueNotifier<List<NeuralGpu>> gpus =
      ValueNotifier<List<NeuralGpu>>(const <NeuralGpu>[]);

  NeuralModelPaths? _realcuganPaths;
  String? _upscaylBinaryPath;
  Future<void>? _initFuture;
  Future<bool>? _downloadFuture;
  bool _gpusLoaded = false;
  bool _gpusLoading = false;

  NeuralModelPaths? get paths => _realcuganPaths;

  /// True when the Real-CUGAN package is installed (backwards-compatible).
  bool get isReady => _realcuganPaths != null;

  /// True when at least one engine + model is installed and runnable.
  bool get isAnyReady =>
      _realcuganPaths != null ||
      NeuralUpscaleModel.values.any(isModelReady);

  bool get isSupportedPlatform => Platform.isWindows || Platform.isLinux;

  String get _realcuganBinaryName => Platform.isWindows
      ? 'realcugan-ncnn-vulkan.exe'
      : 'realcugan-ncnn-vulkan';

  String get _realcuganZipName => Platform.isWindows
      ? 'realcugan-ncnn-vulkan-$_realcuganVersion-windows.zip'
      : 'realcugan-ncnn-vulkan-$_realcuganVersion-ubuntu.zip';

  String get _upscaylBinaryName =>
      Platform.isWindows ? 'upscayl-bin.exe' : 'upscayl-bin';

  String get _upscaylZipName => Platform.isWindows
      ? 'upscayl-bin-$_upscaylVersion-windows.zip'
      : 'upscayl-bin-$_upscaylVersion-linux.zip';

  Directory get _realcuganManagedRoot => Directory(
      p.join(pathService.getCacheDir().path, 'neural_models', _realcuganVersion));

  Directory get _upscaylBinRoot => Directory(p.join(
      pathService.getCacheDir().path, 'neural_models', 'upscayl-$_upscaylVersion'));

  Directory get _upscaylModelsRoot => Directory(
      p.join(pathService.getCacheDir().path, 'neural_models', 'upscayl-models'));

  /// Returns runnable paths for [model], or `null` if its engine or weights
  /// are not installed yet.
  NeuralModelPaths? pathsFor(NeuralUpscaleModel model) {
    if (model.engine == NeuralUpscaleEngine.realcugan) {
      final NeuralModelPaths? rc = _realcuganPaths;
      if (rc == null) {
        return null;
      }
      if (!Directory(rc.modelsDir(model)).existsSync()) {
        return null;
      }
      return rc;
    }

    final String? bin = _upscaylBinaryPath;
    if (bin == null || !File(bin).existsSync()) {
      return null;
    }
    if (!_hasUpscaylModelWeights(model)) {
      return null;
    }
    return NeuralModelPaths(
      binaryPath: bin,
      rootDir: _upscaylModelsRoot.path,
      executableDir: p.dirname(bin),
    );
  }

  /// Whether [model] has both its inference binary and weight files installed.
  bool isModelReady(NeuralUpscaleModel model) => pathsFor(model) != null;

  /// Effective status for a specific [model].
  NeuralModelStatus statusFor(NeuralUpscaleModel model) {
    if (!isSupportedPlatform) {
      return NeuralModelStatus.notAvailable;
    }
    if (downloadingModel.value == model &&
        status.value == NeuralModelStatus.downloading) {
      return NeuralModelStatus.downloading;
    }
    if (isModelReady(model)) {
      return NeuralModelStatus.ready;
    }
    if (status.value == NeuralModelStatus.unknown) {
      return NeuralModelStatus.unknown;
    }
    if (downloadingModel.value == model &&
        status.value == NeuralModelStatus.error) {
      return NeuralModelStatus.error;
    }
    return NeuralModelStatus.notAvailable;
  }

  /// Looks for existing installs of both engines and updates readiness.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    if (!isSupportedPlatform) {
      status.value = NeuralModelStatus.notAvailable;
      return;
    }

    try {
      final List<String> rcCandidates = <String>[
        _realcuganManagedRoot.path,
        p.join(p.dirname(Platform.resolvedExecutable), 'neural_models'),
        p.join(pathService.getVisibleDir().path, 'neural_models'),
      ];

      for (final String candidate in rcCandidates) {
        final NeuralModelPaths? found = _locateRealcugan(candidate);
        if (found != null) {
          _realcuganPaths = found;
          await _ensureExecutable(found.binaryPath);
          log.info('Neural upscaler (Real-CUGAN) ready: ${found.binaryPath}');
          break;
        }
      }

      final List<String> upscaylCandidates = <String>[
        _upscaylBinRoot.path,
        p.join(p.dirname(Platform.resolvedExecutable), 'neural_models'),
        p.join(pathService.getVisibleDir().path, 'neural_models'),
      ];

      for (final String candidate in upscaylCandidates) {
        final String? found = _locateBinary(candidate, _upscaylBinaryName);
        if (found != null) {
          _upscaylBinaryPath = found;
          await _ensureExecutable(found);
          log.info('Neural upscaler (upscayl-ncnn) ready: $found');
          break;
        }
      }
    } catch (e, s) {
      log.error('Neural upscaler init failed: $e\n$s');
      status.value = NeuralModelStatus.error;
      revision.value++;
      return;
    }

    status.value =
        isAnyReady ? NeuralModelStatus.ready : NeuralModelStatus.notAvailable;
    revision.value++;
  }

  /// Downloads and extracts the Real-CUGAN package when not installed yet.
  Future<bool> ensureReady() => ensureModelReady(NeuralUpscaleModel.se);

  /// Downloads and installs the engine binary and weights needed by [model].
  Future<bool> ensureModelReady(NeuralUpscaleModel model) async {
    await init();
    if (isModelReady(model)) {
      return true;
    }
    if (!isSupportedPlatform) {
      status.value = NeuralModelStatus.notAvailable;
      return false;
    }

    // Serialize downloads cleanly so progress reporting stays coherent.
    while (_downloadFuture != null) {
      await _downloadFuture;
      if (isModelReady(model)) {
        return true;
      }
    }

    final Future<bool> future = model.engine == NeuralUpscaleEngine.realcugan
        ? _downloadRealcugan(model)
        : _downloadUpscaylModel(model);
    _downloadFuture = future;
    try {
      return await future;
    } finally {
      _downloadFuture = null;
    }
  }

  Future<bool> _downloadRealcugan(NeuralUpscaleModel model) async {
    final Directory root = _realcuganManagedRoot;
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }

    final File zip = File(p.join(root.path, 'package.zip'));
    final Directory extract = Directory(p.join(root.path, 'package'));
    if (extract.existsSync()) {
      extract.deleteSync(recursive: true);
    }

    downloadingModel.value = model;
    status.value = NeuralModelStatus.downloading;
    downloadProgress.value = 0;

    try {
      await ehRequest.download(
        url: '$_realcuganReleaseBase/$_realcuganZipName',
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

      final NeuralModelPaths? found = _locateRealcugan(extract.path);
      if (found == null) {
        status.value = NeuralModelStatus.error;
        log.error('Neural upscaler: package has no usable binary/models');
        return false;
      }

      await _ensureExecutable(found.binaryPath);
      _realcuganPaths = found;
      _gpusLoaded = false;
      downloadProgress.value = 1;
      downloadingModel.value = null;
      status.value = NeuralModelStatus.ready;
      revision.value++;
      log.info('Neural upscaler (Real-CUGAN) downloaded: ${found.binaryPath}');
      return true;
    } catch (e, s) {
      log.error('Neural upscaler download failed: $e\n$s');
      status.value = NeuralModelStatus.error;
      revision.value++;
      return false;
    }
  }

  Future<bool> _downloadUpscaylModel(NeuralUpscaleModel model) async {
    downloadingModel.value = model;
    status.value = NeuralModelStatus.downloading;
    downloadProgress.value = 0;

    final bool needBinary =
        _upscaylBinaryPath == null || !File(_upscaylBinaryPath!).existsSync();
    final double weightsStart = needBinary ? 0.5 : 0.0;

    try {
      if (needBinary) {
        final bool binOk = await _downloadUpscaylBinary(
          progressStart: 0.0,
          progressEnd: weightsStart,
        );
        if (!binOk) {
          status.value = NeuralModelStatus.error;
          revision.value++;
          return false;
        }
      }

      if (!_hasUpscaylModelWeights(model)) {
        final bool weightsOk = await _downloadUpscaylWeights(
          model,
          progressStart: weightsStart,
          progressEnd: 1.0,
        );
        if (!weightsOk) {
          status.value = NeuralModelStatus.error;
          revision.value++;
          return false;
        }
      }

      if (!isModelReady(model)) {
        log.error('Neural upscaler: downloaded weights missing for ${model.name}');
        status.value = NeuralModelStatus.error;
        revision.value++;
        return false;
      }

      _gpusLoaded = false;
      downloadProgress.value = 1;
      downloadingModel.value = null;
      status.value = NeuralModelStatus.ready;
      revision.value++;
      log.info('Neural upscaler (${model.label}) ready');
      return true;
    } catch (e, s) {
      log.error('Neural upscaler (${model.name}) download failed: $e\n$s');
      status.value = NeuralModelStatus.error;
      revision.value++;
      return false;
    }
  }

  Future<bool> _downloadUpscaylBinary({
    required double progressStart,
    required double progressEnd,
  }) async {
    final Directory root = _upscaylBinRoot;
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }

    final File zip = File(p.join(root.path, 'upscayl-bin.zip'));
    final Directory extract = Directory(p.join(root.path, 'package'));
    if (extract.existsSync()) {
      extract.deleteSync(recursive: true);
    }

    try {
      await ehRequest.download(
        url: '$_upscaylReleaseBase/$_upscaylZipName',
        path: zip.path,
        receiveTimeout: 5 * 60 * 1000,
        onReceiveProgress: (int count, int total) {
          if (total > 0) {
            final double fraction = (count / total).clamp(0.0, 1.0);
            downloadProgress.value =
                progressStart + fraction * (progressEnd - progressStart);
          }
        },
      );

      final bool extracted = await extractZipArchive(zip.path, extract.path);
      if (!extracted) {
        log.error('Neural upscaler: failed to extract ${zip.path}');
        return false;
      }

      final String? binary = _locateBinary(extract.path, _upscaylBinaryName);
      if (binary == null) {
        log.error('Neural upscaler: upscayl-bin missing from archive');
        return false;
      }

      await _ensureExecutable(binary);
      _upscaylBinaryPath = binary;
      return true;
    } finally {
      try {
        if (zip.existsSync()) {
          zip.deleteSync();
        }
      } catch (_) {}
    }
  }

  Future<bool> _downloadUpscaylWeights(
    NeuralUpscaleModel model, {
    required double progressStart,
    required double progressEnd,
  }) async {
    final Directory targetDir =
        Directory(p.join(_upscaylModelsRoot.path, model.directory));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    switch (model) {
      case NeuralUpscaleModel.modernSpanimationV2:
        return _downloadAndFlattenTarGz(
          url: '$_rveModelsBase/2x_ModernSpanimationV2.tar.gz',
          targetDir: targetDir,
          progressStart: progressStart,
          progressEnd: progressEnd,
        );
      case NeuralUpscaleModel.animeJaNaiV3Compact:
        return _downloadAndFlattenTarGz(
          url: '$_rveModelsBase/2x_AnimeJaNai_HD_V3_Sharp1_Compact_430k.tar.gz',
          targetDir: targetDir,
          progressStart: progressStart,
          progressEnd: progressEnd,
        );
      case NeuralUpscaleModel.hfa2kMultiJpgCompact:
        final String name = model.ncnnModelNameForScale(2);
        final double mid = progressStart + (progressEnd - progressStart) * 0.1;
        await _downloadFile(
          url: '$_phhofmHfa2kBase/2xHFA2k_compact_multijpg_fp16.param',
          destPath: p.join(targetDir.path, '$name.param'),
          progressStart: progressStart,
          progressEnd: mid,
        );
        await _downloadFile(
          url: '$_phhofmHfa2kBase/2xHFA2k_compact_multijpg_fp16.bin',
          destPath: p.join(targetDir.path, '$name.bin'),
          progressStart: mid,
          progressEnd: progressEnd,
        );
        return true;
      case NeuralUpscaleModel.animeVideoV3:
        final List<int> scales = model.supportedScales;
        final double step = (progressEnd - progressStart) / scales.length;
        for (int i = 0; i < scales.length; i++) {
          final int s = scales[i];
          final bool ok = await _downloadAndFlattenTarGz(
            url: '$_rveModelsBase/realesr-animevideov3-x$s.tar.gz',
            targetDir: targetDir,
            progressStart: progressStart + step * i,
            progressEnd: progressStart + step * (i + 1),
          );
          if (!ok) {
            return false;
          }
        }
        return true;
      case NeuralUpscaleModel.se:
      case NeuralUpscaleModel.pro:
        return false;
    }
  }

  Future<void> _downloadFile({
    required String url,
    required String destPath,
    required double progressStart,
    required double progressEnd,
  }) async {
    final File temp = File('$destPath.part');
    try {
      await ehRequest.download(
        url: url,
        path: temp.path,
        receiveTimeout: 5 * 60 * 1000,
        onReceiveProgress: (int count, int total) {
          if (total > 0) {
            final double fraction = (count / total).clamp(0.0, 1.0);
            downloadProgress.value =
                progressStart + fraction * (progressEnd - progressStart);
          }
        },
      );
      final File dest = File(destPath);
      if (dest.existsSync()) {
        dest.deleteSync();
      }
      temp.renameSync(destPath);
    } catch (_) {
      try {
        if (temp.existsSync()) {
          temp.deleteSync();
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<bool> _downloadAndFlattenTarGz({
    required String url,
    required Directory targetDir,
    required double progressStart,
    required double progressEnd,
  }) async {
    final Directory tmpDir = Directory(
      p.join(targetDir.path, '_tmp_${DateTime.now().microsecondsSinceEpoch}'),
    );
    tmpDir.createSync(recursive: true);
    final File archiveFile = File(p.join(tmpDir.path, 'model.tar.gz'));
    final Directory extractDir = Directory(p.join(tmpDir.path, 'extracted'));

    try {
      await ehRequest.download(
        url: url,
        path: archiveFile.path,
        receiveTimeout: 5 * 60 * 1000,
        onReceiveProgress: (int count, int total) {
          if (total > 0) {
            final double fraction = (count / total).clamp(0.0, 1.0);
            downloadProgress.value =
                progressStart + fraction * (progressEnd - progressStart);
          }
        },
      );

      final bool extracted =
          await extractTarGzArchive(archiveFile.path, extractDir.path);
      if (!extracted || !extractDir.existsSync()) {
        log.error('Neural upscaler: failed to extract $url');
        return false;
      }

      int copied = 0;
      for (final FileSystemEntity entity
          in extractDir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final String base = p.basename(entity.path);
        if (base.endsWith('.param') || base.endsWith('.bin')) {
          final String dest = p.join(targetDir.path, base);
          entity.copySync(dest);
          copied++;
        }
      }
      return copied >= 2;
    } finally {
      try {
        if (tmpDir.existsSync()) {
          tmpDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }

  bool _hasUpscaylModelWeights(NeuralUpscaleModel model) {
    final String dirPath = p.join(_upscaylModelsRoot.path, model.directory);
    if (!Directory(dirPath).existsSync()) {
      return false;
    }
    for (final int scale in model.supportedScales) {
      final String name = model.ncnnModelNameForScale(scale);
      final File param = File(p.join(dirPath, '$name.param'));
      final File bin = File(p.join(dirPath, '$name.bin'));
      if (!param.existsSync() ||
          !bin.existsSync() ||
          param.lengthSync() == 0 ||
          bin.lengthSync() == 0) {
        return false;
      }
    }
    return true;
  }

  /// Asks an installed ncnn binary to print its Vulkan devices once (a 64x64
  /// dummy input is enough) and parses the `[index name]` lines. Cached for
  /// the app session; call with [force] to refresh after a driver/model change.
  Future<void> refreshGpus({bool force = false}) async {
    if (_gpusLoading || (_gpusLoaded && !force)) {
      return;
    }

    NeuralUpscaleModel? probeModel;
    NeuralModelPaths? probePaths;
    for (final NeuralUpscaleModel candidate in NeuralUpscaleModel.values) {
      final NeuralModelPaths? pth = pathsFor(candidate);
      if (pth != null) {
        probeModel = candidate;
        probePaths = pth;
        break;
      }
    }
    if (probeModel == null || probePaths == null) {
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

      final String modelDir = probePaths.modelsDir(probeModel);
      final List<String> args = probeModel.engine == NeuralUpscaleEngine.realcugan
          ? <String>[
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
            ]
          : <String>[
              '-i',
              input.path,
              '-o',
              output.path,
              '-s',
              '2',
              '-z',
              '2',
              '-m',
              modelDir,
              '-n',
              probeModel.ncnnModelNameForScale(2),
              '-v',
            ];

      final Process process = await Process.start(
        probePaths.binaryPath,
        args,
        workingDirectory: probePaths.executableDir,
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

  NeuralModelPaths? _locateRealcugan(String root) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) {
      return null;
    }

    try {
      for (final FileSystemEntity entity
          in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || p.basename(entity.path) != _realcuganBinaryName) {
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

  String? _locateBinary(String root, String binaryName) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) {
      return null;
    }
    try {
      for (final FileSystemEntity entity
          in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File && p.basename(entity.path) == binaryName) {
          return entity.path;
        }
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
