/// How the neural upscaler behaves for one gallery.
///
/// [on] runs the neural upscaler on every eligible page of the gallery and
/// [off] disables it for this gallery without changing the global setting.
enum GalleryNeuralMode {
  on,
  off;

  /// Order used by the quick toggle: on -> off -> on.
  GalleryNeuralMode get next => switch (this) {
        GalleryNeuralMode.on => GalleryNeuralMode.off,
        GalleryNeuralMode.off => GalleryNeuralMode.on,
      };

  /// Whether pages of this gallery are handed to the neural upscaler.
  bool get allowsNeural => this == GalleryNeuralMode.on;

  /// Translation key with the short label shown in menus.
  String get labelKey => switch (this) {
        GalleryNeuralMode.on => 'galleryNeuralOn',
        GalleryNeuralMode.off => 'galleryNeuralOff',
      };
}
