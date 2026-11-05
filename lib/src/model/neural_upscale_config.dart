import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Model families shipped in the Real-CUGAN ncnn package.
///
/// [se] is the standard edition (more denoise variants); [pro] is the
/// enhanced-line edition (sharper lines, fewer variants).
enum NeuralUpscaleModel { se, pro }

extension NeuralUpscaleModelX on NeuralUpscaleModel {
  String get directory =>
      this == NeuralUpscaleModel.pro ? 'models-pro' : 'models-se';

  String get label => this == NeuralUpscaleModel.pro ? 'Pro' : 'SE';
}

/// Denoise levels understood by `realcugan-ncnn-vulkan` (`-n`).
///
/// `-1` disables denoise; `0` is the conservative model; `1..3` are the
/// increasing denoise weights.
const int neuralDenoiseNone = -1;
const int neuralDenoiseConservative = 0;

/// Largest texture the reader is allowed to allocate for an enhanced page.
const int neuralMaxOutputDimension = 4096;

/// 3x only pays off for genuinely small sources; everything else uses 2x.
int neuralScaleFor(int width, int height) {
  const int three = 3;
  if (width < 900 &&
      width * three <= neuralMaxOutputDimension &&
      height * three <= neuralMaxOutputDimension) {
    return three;
  }
  return 2;
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
  final String raw =
      '$sourceKey|${model.name}|$denoise|$scale|${width}x$height|v1';
  return sha1.convert(utf8.encode(raw)).toString();
}
