import 'package:flutter_test/flutter_test.dart';

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
      expect(neuralScaleFor(700, 2000), 2);
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
