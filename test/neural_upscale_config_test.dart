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
