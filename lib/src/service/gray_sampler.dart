import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:acervo_hc/src/model/gray_metrics.dart';

/// Size of the downscaled copy used by the grayscale probe. Small enough to
/// scan in a couple of milliseconds, large enough to keep colored areas visible.
const int graySampleWidth = 160;
const int graySampleHeight = 400;

/// Measures the chroma of [image] from a tiny downscaled copy.
///
/// Reading the full texture with `rawRgba` costs tens of milliseconds and tens
/// of megabytes per page; downscaling first keeps the probe around 2-5 ms.
/// Returns null when the texture cannot be read, so callers keep their current
/// behavior instead of skipping a page by mistake.
Future<GrayMetrics?> sampleGray(ui.Image image) async {
  if (image.width <= 0 || image.height <= 0) {
    return null;
  }

  final double scale = min(
    graySampleWidth / image.width,
    graySampleHeight / image.height,
  );
  final int width = max(1, (image.width * scale).round());
  final int height = max(1, (image.height * scale).round());

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    ),
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.low,
  );
  final ui.Picture picture = recorder.endRecording();

  ui.Image? thumb;
  try {
    thumb = await picture.toImage(width, height);
    final ByteData? data = await thumb.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (data == null) {
      return null;
    }
    return measureGray(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } catch (_) {
    return null;
  } finally {
    thumb?.dispose();
    picture.dispose();
  }
}
