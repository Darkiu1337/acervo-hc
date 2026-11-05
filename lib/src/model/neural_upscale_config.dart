import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Model families shipped in the Real-CUGAN ncnn package.
///
/// [se] is the standard edition (more denoise variants); [pro] is the
/// enhanced-line edition (sharper lines, fewer variants).
enum NeuralUpscaleModel { se, pro }

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
  String get directory =>
      this == NeuralUpscaleModel.pro ? 'models-pro' : 'models-se';

  String get label => this == NeuralUpscaleModel.pro ? 'Pro' : 'SE';

  /// The Pro package only ships 2x/3x weights.
  int get maxScale => this == NeuralUpscaleModel.pro ? 3 : 4;
}

/// Denoise levels understood by `realcugan-ncnn-vulkan` (`-n`).
///
/// `-1` disables denoise; `0` is the conservative model; `1..3` are the
/// increasing denoise weights.
const int neuralDenoiseNone = -1;
const int neuralDenoiseConservative = 0;

/// Largest texture the reader is allowed to allocate for an enhanced page.
/// 3x on a typical 1280x1800 page is 3840x5400, so the manual 3x option needs a
/// little more room than the old 4096 guard. 4x still only applies to small
/// sources because it doubles both axes again.
const int neuralMaxOutputDimension = 6144;

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
  while (desired > 1 &&
      (width * desired > neuralMaxOutputDimension ||
          height * desired > neuralMaxOutputDimension)) {
    desired--;
  }
  return desired;
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
