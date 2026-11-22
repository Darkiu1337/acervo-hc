import 'package:flutter_test/flutter_test.dart';

import 'package:acervo_hc/src/model/gallery_neural_mode.dart';

void main() {
  test('quick toggle alternates on <-> off', () {
    expect(GalleryNeuralMode.on.next, GalleryNeuralMode.off);
    expect(GalleryNeuralMode.off.next, GalleryNeuralMode.on);
  });

  test('only off disables neural upscale for the gallery', () {
    expect(GalleryNeuralMode.on.allowsNeural, isTrue);
    expect(GalleryNeuralMode.off.allowsNeural, isFalse);
  });

  test('labels differ per mode', () {
    final Set<String> keys =
        GalleryNeuralMode.values.map((GalleryNeuralMode m) => m.labelKey).toSet();
    expect(keys.length, GalleryNeuralMode.values.length);
  });
}
