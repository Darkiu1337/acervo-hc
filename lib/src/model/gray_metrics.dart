import 'dart:typed_data';

/// Chroma above this is treated as real color when deciding whether a page is
/// black and white enough to skip the neural upscaler.
const int grayLenientChroma = 32;

/// A page is "lenient gray" while at most this fraction of its pixels carries
/// that much chroma (tolerates tinted paper, scan noise and small color seals).
const double grayLenientMaxColoredRatio = 0.02;

/// Chroma above this is any noticeable color. Pages under
/// [grayStrictMaxColoredRatio] are forced back to gray after the neural pass,
/// so the model never leaves a magenta cast on them.
const int grayStrictChroma = 18;
const double grayStrictMaxColoredRatio = 0.005;

/// How much chroma an RGBA buffer carries, at two tolerances.
class GrayMetrics {
  const GrayMetrics({
    required this.lenientColoredRatio,
    required this.strictColoredRatio,
  });

  /// Fraction of pixels with chroma above [grayLenientChroma].
  final double lenientColoredRatio;

  /// Fraction of pixels with chroma above [grayStrictChroma].
  final double strictColoredRatio;

  /// Black and white enough to skip the neural upscaler.
  bool get lenientGray => lenientColoredRatio <= grayLenientMaxColoredRatio;

  /// Black and white enough that the neural output must be desaturated.
  bool get strictGray => strictColoredRatio <= grayStrictMaxColoredRatio;
}

/// Measures [rgba] in a single pass, counting both tolerances at once.
GrayMetrics measureGray(Uint8List rgba) {
  final int total = rgba.length ~/ 4;
  if (total == 0) {
    return const GrayMetrics(lenientColoredRatio: 1, strictColoredRatio: 1);
  }

  int lenient = 0;
  int strict = 0;
  for (int i = 0; i < total; i++) {
    final int o = i * 4;
    final int r = rgba[o];
    final int g = rgba[o + 1];
    final int b = rgba[o + 2];
    final int maxv = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final int minv = r < g ? (r < b ? r : b) : (g < b ? g : b);
    final int chroma = maxv - minv;
    if (chroma > grayLenientChroma) {
      lenient++;
      strict++;
    } else if (chroma > grayStrictChroma) {
      strict++;
    }
  }

  return GrayMetrics(
    lenientColoredRatio: lenient / total,
    strictColoredRatio: strict / total,
  );
}
