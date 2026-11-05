/// One Vulkan device exposed by the ncnn binary.
class NeuralGpu {
  final int index;
  final String name;

  const NeuralGpu(this.index, this.name);
}

final RegExp _gpuLine = RegExp(r'^\s*\[(\d+)\s+([^\]]+?)\]', multiLine: true);

/// Parses the device list printed by `realcugan-ncnn-vulkan -v`:
///
/// ```
/// [0 NVIDIA GeForce GTX 1650]  queueC=2[8] ...
/// [1 AMD Radeon(TM) Graphics]  queueC=1[2] ...
/// ```
///
/// Each device is printed several times (queue, fp16, subgroup lines); the
/// index is used to keep only the first name per device.
List<NeuralGpu> parseNeuralGpus(String stderr) {
  final Map<int, String> found = <int, String>{};
  for (final RegExpMatch match in _gpuLine.allMatches(stderr)) {
    final int? index = int.tryParse(match.group(1) ?? '');
    final String name = (match.group(2) ?? '').trim();
    if (index != null && name.isNotEmpty) {
      found[index] = name;
    }
  }
  final List<NeuralGpu> result = found.entries
      .map((MapEntry<int, String> entry) => NeuralGpu(entry.key, entry.value))
      .toList()
    ..sort((NeuralGpu a, NeuralGpu b) => a.index.compareTo(b.index));
  return result;
}
