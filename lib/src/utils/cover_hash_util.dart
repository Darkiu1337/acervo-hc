import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:acervo_hc/src/network/xlecx_request.dart';
import 'package:acervo_hc/src/utils/gallery_identity_matcher.dart';

/// Computes 128-bit perceptual hashes ([CoverPerceptualHash]) of gallery covers
/// using Flutter's native image codec resized directly to 9x9 pixels.
///
/// Always checks `extended_image`'s disk cache first so already-displayed
/// covers require zero extra network traffic.
class CoverHashUtil {
  static String normalizeCoverUrl(String url) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      final Uri uri = Uri.parse(trimmed);
      if (uri.host == 's.exhentai.org') {
        return uri.replace(host: 'ehgt.org').toString();
      }
    } catch (_) {
      // Keep original url if parsing fails.
    }
    return trimmed;
  }

  /// Decodes raw image bytes directly at 9x9 via the platform codec and returns
  /// a 128-bit perceptual gradient hash, or `null` if decoding fails or the
  /// image has too little visual structure.
  static Future<CoverPerceptualHash?> computeFromBytes(Uint8List bytes) async {
    if (bytes.isEmpty) {
      return null;
    }

    ui.Codec? codec;
    ui.FrameInfo? frame;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 9,
        targetHeight: 9,
      );
      frame = await codec.getNextFrame();
      final ByteData? byteData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        return null;
      }
      return CoverPerceptualHash.fromRgba9x9(byteData.buffer.asUint8List());
    } catch (_) {
      return null;
    } finally {
      frame?.image.dispose();
      codec?.dispose();
    }
  }

  /// Resolves the cover bytes (disk cache first, optional network fallback) and
  /// computes its [CoverPerceptualHash].
  static Future<CoverPerceptualHash?> computeForUrl(
    String rawUrl, {
    bool allowNetwork = true,
  }) async {
    final String url = normalizeCoverUrl(rawUrl);
    if (url.isEmpty) {
      return null;
    }

    Uint8List? bytes;

    /// 1. Disk cache hit (zero network traffic when the card/detail already rendered).
    try {
      final File? cached = await getCachedImageFile(url);
      if (cached != null && await cached.exists()) {
        bytes = await cached.readAsBytes();
      }
    } catch (_) {
      // Ignore cache read errors and fall through to optional network fetch.
    }

    /// 2. Network fallback (only when allowed).
    if ((bytes == null || bytes.isEmpty) && allowNetwork) {
      bytes = await _fetchBytes(url);
    }

    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    return computeFromBytes(bytes);
  }

  static Future<Uint8List?> _fetchBytes(String url) async {
    try {
      if (url.contains('xlecx.one')) {
        final Response<List<int>> response = await xlecxRequest.dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            validateStatus: (int? status) => status != null && status >= 200 && status < 300,
          ),
        );
        final List<int>? data = response.data;
        if (data == null || data.isEmpty) {
          return null;
        }
        return data is Uint8List ? data : Uint8List.fromList(data);
      }

      return await getNetworkImageData(url, useCache: true);
    } catch (_) {
      return null;
    }
  }
}
