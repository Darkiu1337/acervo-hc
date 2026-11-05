import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:acervo_hc/src/model/gray_metrics.dart';

Uint8List _buffer(List<List<int>> pixels) {
  final Uint8List rgba = Uint8List(pixels.length * 4);
  for (int i = 0; i < pixels.length; i++) {
    final List<int> pixel = pixels[i];
    rgba[i * 4] = pixel[0];
    rgba[i * 4 + 1] = pixel[1];
    rgba[i * 4 + 2] = pixel[2];
    rgba[i * 4 + 3] = 255;
  }
  return rgba;
}

List<List<int>> _fill(int count, List<int> pixel) =>
    List<List<int>>.generate(count, (_) => pixel);

void main() {
  group('measureGray', () {
    test('neutral pixels are gray at both tolerances', () {
      final GrayMetrics metrics = measureGray(_buffer(_fill(100, <int>[128, 128, 128])));

      expect(metrics.lenientColoredRatio, 0);
      expect(metrics.strictColoredRatio, 0);
      expect(metrics.lenientGray, isTrue);
      expect(metrics.strictGray, isTrue);
    });

    test('a colored page is not gray at either tolerance', () {
      final GrayMetrics metrics = measureGray(_buffer(_fill(100, <int>[220, 30, 30])));

      expect(metrics.lenientGray, isFalse);
      expect(metrics.strictGray, isFalse);
    });

    test('a small colored detail skips the neural but still desaturates', () {
      final List<List<int>> pixels = <List<int>>[
        ..._fill(10, <int>[220, 30, 30]),
        ..._fill(990, <int>[200, 200, 200]),
      ];
      final GrayMetrics metrics = measureGray(_buffer(pixels));

      expect(metrics.lenientColoredRatio, closeTo(0.01, 0.0001));
      expect(metrics.lenientGray, isTrue);
      expect(metrics.strictGray, isFalse);
    });

    test('a faint tint is not enough to keep the neural pass', () {
      final List<List<int>> pixels = <List<int>>[
        ..._fill(10, <int>[210, 200, 200]),
        ..._fill(990, <int>[200, 200, 200]),
      ];
      final GrayMetrics metrics = measureGray(_buffer(pixels));

      /// Chroma 10 is below both tolerances: the page is a plain scan.
      expect(metrics.lenientColoredRatio, 0);
      expect(metrics.strictColoredRatio, 0);
    });

    test('lenient threshold stops exactly above two percent', () {
      final List<List<int>> atLimit = <List<int>>[
        ..._fill(20, <int>[220, 30, 30]),
        ..._fill(980, <int>[200, 200, 200]),
      ];
      final List<List<int>> aboveLimit = <List<int>>[
        ..._fill(21, <int>[220, 30, 30]),
        ..._fill(979, <int>[200, 200, 200]),
      ];

      expect(measureGray(_buffer(atLimit)).lenientGray, isTrue);
      expect(measureGray(_buffer(aboveLimit)).lenientGray, isFalse);
    });

    test('an empty buffer is reported as colored', () {
      final GrayMetrics metrics = measureGray(Uint8List(0));

      expect(metrics.lenientGray, isFalse);
      expect(metrics.strictGray, isFalse);
    });
  });
}
