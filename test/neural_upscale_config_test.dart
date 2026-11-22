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

    test('allows 2x for tall webtoon and wide hi-res comic pages within 36MP budget', () {
      expect(neuralScaleFor(1280, 3600, NeuralUpscaleScale.auto), 2);
      expect(neuralScaleFor(2000, 3200, NeuralUpscaleScale.x2), 2);
    });

    test('returns 1 when even 2x does not fit, so the caller skips', () {
      expect(neuralScaleFor(4000, 4000, NeuralUpscaleScale.x2), 1);
      expect(neuralScaleFor(1280, 4500, NeuralUpscaleScale.x2), 1);
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

    test('produces distinct keys for every neural model', () {
      final Set<String> keys = NeuralUpscaleModel.values
          .map((NeuralUpscaleModel m) => key(model: m))
          .toSet();
      expect(keys.length, NeuralUpscaleModel.values.length);
    });

    test('ignores Real-CUGAN denoise setting for non-denoise models', () {
      expect(
        key(model: NeuralUpscaleModel.modernSpanimationV2, denoise: -1),
        key(model: NeuralUpscaleModel.modernSpanimationV2, denoise: 3),
      );
      expect(
        key(model: NeuralUpscaleModel.animeJaNaiV3Compact, denoise: 0),
        key(model: NeuralUpscaleModel.animeJaNaiV3Compact, denoise: 2),
      );
    });
  });

  group('NeuralUpscaleModel metadata & CLI args', () {
    test('preserves legacy enum indices for Real-CUGAN SE and Pro', () {
      expect(NeuralUpscaleModel.se.index, 0);
      expect(NeuralUpscaleModel.pro.index, 1);
    });

    test('maps engines, denoise support, and max scales accurately', () {
      expect(NeuralUpscaleModel.se.engine, NeuralUpscaleEngine.realcugan);
      expect(NeuralUpscaleModel.se.supportsDenoise, isTrue);
      expect(NeuralUpscaleModel.se.maxScale, 4);

      expect(NeuralUpscaleModel.pro.engine, NeuralUpscaleEngine.realcugan);
      expect(NeuralUpscaleModel.pro.supportsDenoise, isTrue);
      expect(NeuralUpscaleModel.pro.maxScale, 3);

      for (final NeuralUpscaleModel m in const <NeuralUpscaleModel>[
        NeuralUpscaleModel.modernSpanimationV2,
        NeuralUpscaleModel.animeJaNaiV3Compact,
        NeuralUpscaleModel.hfa2kMultiJpgCompact,
      ]) {
        expect(m.engine, NeuralUpscaleEngine.upscayl);
        expect(m.supportsDenoise, isFalse);
        expect(m.maxScale, 2);
        expect(m.supportedScales, const <int>[2]);
      }

      expect(NeuralUpscaleModel.animeVideoV3.engine, NeuralUpscaleEngine.upscayl);
      expect(NeuralUpscaleModel.animeVideoV3.supportsDenoise, isFalse);
      expect(NeuralUpscaleModel.animeVideoV3.maxScale, 4);
      expect(NeuralUpscaleModel.animeVideoV3.ncnnModelNameForScale(2),
          'realesr-animevideov3-x2');
      expect(NeuralUpscaleModel.animeVideoV3.ncnnModelNameForScale(3),
          'realesr-animevideov3-x3');
      expect(NeuralUpscaleModel.animeVideoV3.ncnnModelNameForScale(4),
          'realesr-animevideov3-x4');
    });

    test('builds Real-CUGAN args with denoise flag and safe tiling', () {
      final List<String> args = buildNeuralProcessArgs(
        model: NeuralUpscaleModel.se,
        inputPath: '/tmp/in.jpg',
        outputPath: '/tmp/out.png',
        modelDir: '/models/models-se',
        scale: 2,
        denoise: 1,
        gpuId: 0,
        tileSize: 200,
      );
      expect(args, <String>[
        '-i', '/tmp/in.jpg',
        '-o', '/tmp/out.png',
        '-s', '2',
        '-n', '1',
        '-m', '/models/models-se',
        '-g', '0',
        '-f', 'png',
        '-t', '200',
        '-j', '1:1:1',
      ]);
    });

    test('builds Upscayl args with model scale (-z) and ncnn model name (-n)', () {
      final List<String> spanArgs = buildNeuralProcessArgs(
        model: NeuralUpscaleModel.modernSpanimationV2,
        inputPath: '/tmp/in.jpg',
        outputPath: '/tmp/out.png',
        modelDir: '/models/2x_ModernSpanimationV2',
        scale: 2,
        denoise: 0,
        gpuId: 0,
        tileSize: 200,
      );
      expect(spanArgs, <String>[
        '-i', '/tmp/in.jpg',
        '-o', '/tmp/out.png',
        '-s', '2',
        '-z', '2',
        '-m', '/models/2x_ModernSpanimationV2',
        '-n', '2x_ModernSpanimationV2',
        '-g', '0',
        '-f', 'png',
        '-t', '200',
        '-j', '1:1:1',
      ]);

      final List<String> av3Args = buildNeuralProcessArgs(
        model: NeuralUpscaleModel.animeVideoV3,
        inputPath: '/tmp/in.jpg',
        outputPath: '/tmp/out.png',
        modelDir: '/models/realesr-animevideov3',
        scale: 3,
        denoise: 0,
        gpuId: 1,
        tileSize: 200,
      );
      expect(av3Args, containsAllInOrder(<String>[
        '-s', '3',
        '-z', '3',
        '-m', '/models/realesr-animevideov3',
        '-n', 'realesr-animevideov3-x3',
        '-g', '1',
      ]));
    });
  });
}
