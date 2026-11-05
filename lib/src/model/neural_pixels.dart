import 'dart:typed_data';

/// Whether an RGBA buffer is effectively a grayscale page.
///
/// Real-CUGAN is trained on color anime and can hallucinate a magenta/purple
/// chroma cast on pure black-and-white manga, especially with the no-denoise
/// weights. When the source is grayscale we force the result back to gray.
bool isGrayscaleRgba(
  Uint8List rgba, {
  int saturatedDelta = 18,
  double maxColoredRatio = 0.005,
}) {
  final int total = rgba.length ~/ 4;
  if (total == 0) {
    return false;
  }

  int colored = 0;
  for (int i = 0; i < total; i++) {
    final int o = i * 4;
    final int r = rgba[o];
    final int g = rgba[o + 1];
    final int b = rgba[o + 2];
    final int maxv = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final int minv = r < g ? (r < b ? r : b) : (g < b ? g : b);
    if (maxv - minv > saturatedDelta) {
      colored++;
      if (colored / total > maxColoredRatio) {
        return false;
      }
    }
  }
  return true;
}

/// Converts an RGBA buffer to luminance, preserving alpha.
Uint8List desaturateRgba(Uint8List rgba) {
  final Uint8List out = Uint8List.fromList(rgba);
  for (int i = 0; i < out.length; i += 4) {
    final int y = (out[i] * 299 + out[i + 1] * 587 + out[i + 2] * 114) ~/ 1000;
    out[i] = y;
    out[i + 1] = y;
    out[i + 2] = y;
  }
  return out;
}
