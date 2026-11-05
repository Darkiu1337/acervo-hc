/// How the neural upscaler behaves for one gallery.
///
/// The per-page grayscale check always runs while the gallery is [auto]: gray
/// pages skip the model and keep the plain image. [on] forces every page
/// through the model (still desaturated when the source is gray) and [off]
/// skips the gallery entirely.
enum GalleryNeuralMode {
  auto,
  on,
  off;

  /// Order used by the quick toggle: auto -> on -> off -> auto.
  GalleryNeuralMode get next => switch (this) {
        GalleryNeuralMode.auto => GalleryNeuralMode.on,
        GalleryNeuralMode.on => GalleryNeuralMode.off,
        GalleryNeuralMode.off => GalleryNeuralMode.auto,
      };

  /// Whether pages of this gallery are handed to the neural upscaler at all.
  bool get allowsNeural => this != GalleryNeuralMode.off;

  /// Whether grayscale pages are processed instead of skipped.
  bool get forcesGrayscale => this == GalleryNeuralMode.on;

  /// Translation key with the short label shown in menus.
  String get labelKey => switch (this) {
        GalleryNeuralMode.auto => 'galleryNeuralAuto',
        GalleryNeuralMode.on => 'galleryNeuralOn',
        GalleryNeuralMode.off => 'galleryNeuralOff',
      };
}
