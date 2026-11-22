import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Inference binary family backing a [NeuralUpscaleModel].
enum NeuralUpscaleEngine {
  /// `realcugan-ncnn-vulkan` (supports `-n` denoise levels).
  realcugan,

  /// `upscayl-bin` (`upscayl-ncnn`, supports SPAN, SRVGGNetCompact, Real-ESRGAN).
  upscayl,
}

/// Neural upscaler models available in the reader.
///
/// Existing indices (`se = 0`, `pro = 1`) must remain stable because
/// [ReadSetting] persists this enum by index.
enum NeuralUpscaleModel {
  se,
  pro,
  modernSpanimationV2,
  animeJaNaiV3Compact,
  hfa2kMultiJpgCompact,
  animeVideoV3,
}

/// Requested output scale of the neural pass. The service falls back to the
/// largest scale that still fits [neuralMaxOutputDimension].
enum NeuralUpscaleScale { auto, x2, x3, x4 }

extension NeuralUpscaleScaleX on NeuralUpscaleScale {
  String get label => switch (this) {
        NeuralUpscaleScale.auto => 'Auto',
        NeuralUpscaleScale.x2 => '2×',
        NeuralUpscaleScale.x3 => '3×',
        NeuralUpscaleScale.x4 => '4×',
      };

  int get numeric => switch (this) {
        NeuralUpscaleScale.auto => 0,
        NeuralUpscaleScale.x2 => 2,
        NeuralUpscaleScale.x3 => 3,
        NeuralUpscaleScale.x4 => 4,
      };
}

extension NeuralUpscaleModelX on NeuralUpscaleModel {
  NeuralUpscaleEngine get engine => switch (this) {
        NeuralUpscaleModel.se ||
        NeuralUpscaleModel.pro =>
          NeuralUpscaleEngine.realcugan,
        NeuralUpscaleModel.modernSpanimationV2 ||
        NeuralUpscaleModel.animeJaNaiV3Compact ||
        NeuralUpscaleModel.hfa2kMultiJpgCompact ||
        NeuralUpscaleModel.animeVideoV3 =>
          NeuralUpscaleEngine.upscayl,
      };

  /// Subfolder containing this model's `.param`/`.bin` weights under its
  /// engine's root directory.
  String get directory => switch (this) {
        NeuralUpscaleModel.se => 'models-se',
        NeuralUpscaleModel.pro => 'models-pro',
        NeuralUpscaleModel.modernSpanimationV2 => '2x_ModernSpanimationV2',
        NeuralUpscaleModel.animeJaNaiV3Compact =>
          '2x_AnimeJaNai_HD_V3_Sharp1_Compact_430k',
        NeuralUpscaleModel.hfa2kMultiJpgCompact => '2xHFA2k_compact_multijpg',
        NeuralUpscaleModel.animeVideoV3 => 'realesr-animevideov3',
      };

  String get label => switch (this) {
        NeuralUpscaleModel.se => 'Real-CUGAN SE',
        NeuralUpscaleModel.pro => 'Real-CUGAN Pro',
        NeuralUpscaleModel.modernSpanimationV2 =>
          'ModernSpanimation V2 (SPAN 2×)',
        NeuralUpscaleModel.animeJaNaiV3Compact => 'AnimeJaNai V3 Sharp (2×)',
        NeuralUpscaleModel.hfa2kMultiJpgCompact => 'HFA2k Multi-JPG (2×)',
        NeuralUpscaleModel.animeVideoV3 => 'Real-ESRGAN AnimeVideo v3',
      };

  /// Localization key describing what this model is best suited for.
  String get descriptionKey => switch (this) {
        NeuralUpscaleModel.se => 'neuralModelDescSe',
        NeuralUpscaleModel.pro => 'neuralModelDescPro',
        NeuralUpscaleModel.modernSpanimationV2 => 'neuralModelDescSpanV2',
        NeuralUpscaleModel.animeJaNaiV3Compact => 'neuralModelDescAnimeJaNai',
        NeuralUpscaleModel.hfa2kMultiJpgCompact => 'neuralModelDescHfa2k',
        NeuralUpscaleModel.animeVideoV3 => 'neuralModelDescAnimeVideoV3',
      };

  /// Only Real-CUGAN exposes `-n` denoise weights.
  bool get supportsDenoise => engine == NeuralUpscaleEngine.realcugan;

  /// Native maximum scale shipped for this model.
  int get maxScale => switch (this) {
        NeuralUpscaleModel.se || NeuralUpscaleModel.animeVideoV3 => 4,
        NeuralUpscaleModel.pro => 3,
        NeuralUpscaleModel.modernSpanimationV2 ||
        NeuralUpscaleModel.animeJaNaiV3Compact ||
        NeuralUpscaleModel.hfa2kMultiJpgCompact =>
          2,
      };

  /// Supported scale multipliers that have native weight files on disk.
  List<int> get supportedScales => switch (this) {
        NeuralUpscaleModel.se || NeuralUpscaleModel.animeVideoV3 =>
          const <int>[2, 3, 4],
        NeuralUpscaleModel.pro => const <int>[2, 3],
        NeuralUpscaleModel.modernSpanimationV2 ||
        NeuralUpscaleModel.animeJaNaiV3Compact ||
        NeuralUpscaleModel.hfa2kMultiJpgCompact =>
          const <int>[2],
      };

  /// Approximate download size hint shown in settings when not yet installed.
  String get downloadSizeHint => switch (this) {
        NeuralUpscaleModel.se || NeuralUpscaleModel.pro => '~46 MB',
        NeuralUpscaleModel.animeVideoV3 => '~6 MB',
        NeuralUpscaleModel.modernSpanimationV2 ||
        NeuralUpscaleModel.animeJaNaiV3Compact ||
        NeuralUpscaleModel.hfa2kMultiJpgCompact =>
          '~4 MB',
      };

  /// Model name passed to `upscayl-bin -n <name>` for [scale].
  /// Not used for Real-CUGAN models.
  String ncnnModelNameForScale(int scale) => switch (this) {
        NeuralUpscaleModel.se => 'models-se',
        NeuralUpscaleModel.pro => 'models-pro',
        NeuralUpscaleModel.modernSpanimationV2 => '2x_ModernSpanimationV2',
        NeuralUpscaleModel.animeJaNaiV3Compact =>
          '2x_AnimeJaNai_HD_V3_Sharp1_Compact_430k',
        NeuralUpscaleModel.hfa2kMultiJpgCompact => '2xHFA2k_compact_multijpg',
        NeuralUpscaleModel.animeVideoV3 => 'realesr-animevideov3-x$scale',
      };
}

/// Denoise levels understood by `realcugan-ncnn-vulkan` (`-n`).
///
/// `-1` disables denoise; `0` is the conservative model; `1..3` are the
/// increasing denoise weights.
const int neuralDenoiseNone = -1;
const int neuralDenoiseConservative = 0;

/// Largest texture axis allowed for 3x/4x upscales.
const int neuralMaxOutputDimension = 6144;

/// Largest texture axis allowed for 2x upscales (handles tall webtoons and wide
/// 2000-2400px scans without silently falling back to 1x), bounded by
/// [neuralMaxOutputPixels] so VRAM per texture stays safe.
const int neuralMax2xOutputDimension = 8192;
const int neuralMaxOutputPixels = 36 * 1024 * 1024;

/// Effective scale for [width] x [height].
///
/// [requested] is the user preference; when it does not fit the texture guard
/// the next smaller scale is used. A result of 1 means the source is too large
/// for the neural pass and the caller should skip it.
int neuralScaleFor(
  int width,
  int height, [
  NeuralUpscaleScale requested = NeuralUpscaleScale.auto,
  int maxScale = 4,
]) {
  int desired = switch (requested) {
    NeuralUpscaleScale.auto => width < 900 ? 3 : 2,
    NeuralUpscaleScale.x2 => 2,
    NeuralUpscaleScale.x3 => 3,
    NeuralUpscaleScale.x4 => 4,
  };

  if (desired > maxScale) {
    desired = maxScale;
  }
  while (desired > 1 && !_fitsTextureBudget(width, height, desired)) {
    desired--;
  }
  return desired;
}

bool _fitsTextureBudget(int width, int height, int scale) {
  final int outW = width * scale;
  final int outH = height * scale;
  final int maxAxis =
      scale == 2 ? neuralMax2xOutputDimension : neuralMaxOutputDimension;
  if (outW > maxAxis || outH > maxAxis) {
    return false;
  }
  return outW * outH <= neuralMaxOutputPixels;
}

/// Builds the CLI arguments for the selected [model]'s inference binary.
List<String> buildNeuralProcessArgs({
  required NeuralUpscaleModel model,
  required String inputPath,
  required String outputPath,
  required String modelDir,
  required int scale,
  required int denoise,
  required int gpuId,
  required int tileSize,
}) {
  if (model.engine == NeuralUpscaleEngine.realcugan) {
    return <String>[
      '-i',
      inputPath,
      '-o',
      outputPath,
      '-s',
      '$scale',
      '-n',
      '$denoise',
      '-m',
      modelDir,
      '-g',
      '$gpuId',
      '-f',
      'png',
      '-t',
      '$tileSize',
      '-j',
      '1:1:1',
    ];
  }

  return <String>[
    '-i',
    inputPath,
    '-o',
    outputPath,
    '-s',
    '$scale',
    '-z',
    '$scale',
    '-m',
    modelDir,
    '-n',
    model.ncnnModelNameForScale(scale),
    '-g',
    '$gpuId',
    '-f',
    'png',
    '-t',
    '$tileSize',
    '-j',
    '1:1:1',
  ];
}

/// Cache identity: source + model + denoise + scale + dimensions + version.
String neuralCacheKey({
  required String sourceKey,
  required NeuralUpscaleModel model,
  required int denoise,
  required int scale,
  required int width,
  required int height,
}) {
  final int effectiveDenoise = model.supportsDenoise ? denoise : 0;
  final String raw =
      '$sourceKey|${model.name}|$effectiveDenoise|$scale|${width}x$height|v2';
  return sha1.convert(utf8.encode(raw)).toString();
}
