import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'package:acervo_hc/src/model/neural_gpu.dart';
import 'package:acervo_hc/src/model/neural_pixels.dart';
import 'package:acervo_hc/src/model/neural_upscale_config.dart';

void main() {
  group('neuralScaleFor', () {
    test('uses 2x for normal reader pages', () {
      expect(neuralScaleFor(1280, 1800), 2);
      expect(neuralScaleFor(1000, 1400), 2);
    });

    test('uses 3x for small sources while it fits the texture budget', () {
      expect(neuralScaleFor(800, 1200), 3);
      expect(neuralScaleFor(700, 1200), 3);
    });

    test('falls back to 2x when 3x would exceed the budget', () {
      expect(neuralScaleFor(1200, 1400), 2);
      expect(neuralScaleFor(700, 2200), 2);
      expect(neuralScaleFor(800, 2100), 2);
    });

    test('honours the manual 2x/3x/4x preference', () {
      expect(neuralScaleFor(1280, 1800, NeuralUpscaleScale.x3), 3);
      expect(neuralScaleFor(1280, 1800, NeuralUpscaleScale.x4), 3);
      expect(neuralScaleFor(800, 1200, NeuralUpscaleScale.x4), 4);
      expect(neuralScaleFor(2000, 3000, NeuralUpscaleScale.x4), 2);
    });

    test('Pro caps the scale at 3x', () {
      expect(neuralScaleFor(800, 1200, NeuralUpscaleScale.x4, 3), 3);
      expect(neuralScaleFor(1280, 1800, NeuralUpscaleScale.x4, 3), 3);
    });

    test('returns 1 when even 2x does not fit, so the caller skips', () {
      expect(neuralScaleFor(4000, 4000, NeuralUpscaleScale.x2), 1);
    });
  });

  group('neural pixels', () {
    test('detects a neutral grayscale buffer', () {
      final Uint8List rgba = Uint8List(4 * 100);
      for (int i = 0; i < rgba.length; i += 4) {
        rgba[i] = 128;
        rgba[i + 1] = 128;
        rgba[i + 2] = 128;
        rgba[i + 3] = 255;
      }
      expect(isGrayscaleRgba(rgba), isTrue);
    });

    test('rejects a buffer with meaningful color', () {
      final Uint8List rgba = Uint8List(4 * 100);
      for (int i = 0; i < rgba.length; i += 4) {
        rgba[i] = 220;
        rgba[i + 1] = 20;
        rgba[i + 2] = 20;
        rgba[i + 3] = 255;
      }
      expect(isGrayscaleRgba(rgba), isFalse);
    });

    test('desaturation keeps alpha and equalizes RGB', () {
      final Uint8List rgba = Uint8List.fromList(<int>[200, 100, 50, 77]);
      final Uint8List gray = desaturateRgba(rgba);
      expect(gray[0], gray[1]);
      expect(gray[1], gray[2]);
      expect(gray[3], 77);
    });
  });

  group('parseNeuralGpus', () {
    test('keeps one name per ncnn device and sorts by index', () {
      const String stderr = '''
[0 NVIDIA GeForce GTX 1650]  queueC=2[8]  queueG=0[16]
[0 NVIDIA GeForce GTX 1650]  fp16-p/s/a=1/1/1
[0 NVIDIA GeForce GTX 1650]  subgroup=32
[1 AMD Radeon(TM) Graphics]  queueC=1[2]
[1 AMD Radeon(TM) Graphics]  fp16-p/s/a=1/1/1
''';
      final List<NeuralGpu> gpus = parseNeuralGpus(stderr);
      expect(gpus.length, 2);
      expect(gpus[0].index, 0);
      expect(gpus[0].name, 'NVIDIA GeForce GTX 1650');
      expect(gpus[1].index, 1);
      expect(gpus[1].name, 'AMD Radeon(TM) Graphics');
    });

    test('returns an empty list when there is no device line', () {
      expect(parseNeuralGpus('no devices here'), isEmpty);
    });
  });

  group('neuralCacheKey', () {
    String key({
      String source = 'https://example.test/page.jpg',
      NeuralUpscaleModel model = NeuralUpscaleModel.se,
      int denoise = 0,
      int scale = 2,
      int width = 1280,
      int height = 1800,
    }) {
      return neuralCacheKey(
        sourceKey: source,
        model: model,
        denoise: denoise,
        scale: scale,
        width: width,
        height: height,
      );
    }

    test('is stable for the same input', () {
      expect(key(), key());
      expect(key().length, 40);
    });

    test('changes with model, denoise and scale', () {
      expect(key(), isNot(key(model: NeuralUpscaleModel.pro)));
      expect(key(), isNot(key(denoise: 1)));
      expect(key(), isNot(key(scale: 3)));
    });

    test('changes with source and dimensions', () {
      expect(key(), isNot(key(source: 'https://example.test/other.jpg')));
      expect(key(), isNot(key(width: 1200)));
    });
  });
}
