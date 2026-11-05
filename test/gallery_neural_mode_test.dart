import 'package:flutter_test/flutter_test.dart';
import 'package:acervo_hc/src/model/gallery_neural_mode.dart';

void main() {
  test('quick toggle cycles auto -> on -> off -> auto', () {
    expect(GalleryNeuralMode.auto.next, GalleryNeuralMode.on);
    expect(GalleryNeuralMode.on.next, GalleryNeuralMode.off);
    expect(GalleryNeuralMode.off.next, GalleryNeuralMode.auto);
  });

  test('only off removes the neural from the gallery', () {
    expect(GalleryNeuralMode.auto.allowsNeural, isTrue);
    expect(GalleryNeuralMode.on.allowsNeural, isTrue);
    expect(GalleryNeuralMode.off.allowsNeural, isFalse);
  });

  test('only on forces grayscale pages through the model', () {
    expect(GalleryNeuralMode.auto.forcesGrayscale, isFalse);
    expect(GalleryNeuralMode.on.forcesGrayscale, isTrue);
    expect(GalleryNeuralMode.off.forcesGrayscale, isFalse);
  });

  test('labels differ per mode', () {
    final Set<String> keys =
        GalleryNeuralMode.values.map((GalleryNeuralMode mode) => mode.labelKey).toSet();

    expect(keys.length, GalleryNeuralMode.values.length);
  });
}
