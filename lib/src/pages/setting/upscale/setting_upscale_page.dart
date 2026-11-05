import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:acervo_hc/src/model/neural_gpu.dart';
import 'package:acervo_hc/src/model/neural_upscale_config.dart';
import 'package:acervo_hc/src/service/neural_model_manager.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';

/// All image-enhancement settings in one place: the on-demand neural upscaler
/// (model, scale, denoise, preload, GPU) and the managed model install.
class SettingUpscalePage extends StatelessWidget {
  const SettingUpscalePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text('upscale'.tr)),
      body: Obx(() {
        neuralModelManager.init();
        final bool proModel =
            readSetting.neuralUpscaleModel.value == NeuralUpscaleModel.pro;
        final List<int> denoiseValues =
            proModel ? <int>[-1, 0, 3] : <int>[-1, 0, 1, 2, 3];
        final int denoise =
            denoiseValues.contains(readSetting.neuralUpscaleDenoise.value)
                ? readSetting.neuralUpscaleDenoise.value
                : 0;
        final int maxScale = readSetting.neuralUpscaleModel.value.maxScale;
        final List<NeuralUpscaleScale> scaleValues = NeuralUpscaleScale.values
            .where((NeuralUpscaleScale scale) =>
                scale == NeuralUpscaleScale.auto || scale.numeric <= maxScale)
            .toList();
        final NeuralUpscaleScale scale =
            scaleValues.contains(readSetting.neuralUpscaleScale.value)
                ? readSetting.neuralUpscaleScale.value
                : NeuralUpscaleScale.auto;

        return ListView(
          padding: const EdgeInsets.only(top: 16),
          children: [
            SwitchListTile(
              title: Text('enableNeuralUpscale'.tr),
              subtitle: Text('enableNeuralUpscaleHint'.tr),
              value: readSetting.enableNeuralUpscale.value,
              onChanged: (bool value) async {
                if (value) {
                  final bool ready = await neuralModelManager.ensureReady();
                  if (!ready) {
                    toast('neuralUpscaleDownloadFailed'.tr);
                    return;
                  }
                }
                readSetting.saveEnableNeuralUpscale(value);
              },
            ),
            ValueListenableBuilder<NeuralModelStatus>(
              valueListenable: neuralModelManager.status,
              builder: (BuildContext context, NeuralModelStatus status,
                  Widget? child) {
                if (status == NeuralModelStatus.ready) {
                  neuralModelManager.refreshGpus();
                  return ListTile(
                    leading:
                        const Icon(Icons.check_circle, color: Colors.green),
                    title: Text('neuralUpscaleModelReady'.tr),
                    subtitle: Text('neuralUpscaleModelReadyHint'.tr),
                  );
                }
                if (status == NeuralModelStatus.downloading) {
                  return ValueListenableBuilder<double>(
                    valueListenable: neuralModelManager.downloadProgress,
                    builder:
                        (BuildContext context, double progress, Widget? child) {
                      return ListTile(
                        leading: const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        title: Text('neuralUpscaleDownloading'.tr),
                        subtitle: LinearProgressIndicator(value: progress),
                      );
                    },
                  );
                }
                return ListTile(
                  leading: const Icon(Icons.download),
                  title: Text('neuralUpscaleDownloadModel'.tr),
                  subtitle: Text('neuralUpscaleDownloadModelHint'.tr),
                  trailing: TextButton(
                    onPressed: () async {
                      final bool ok = await neuralModelManager.ensureReady();
                      if (!ok) {
                        toast('neuralUpscaleDownloadFailed'.tr);
                      }
                    },
                    child: Text('download'.tr),
                  ),
                );
              },
            ),
            ListTile(
              title: Text('neuralUpscaleModel'.tr),
              trailing: DropdownButton<NeuralUpscaleModel>(
                value: readSetting.neuralUpscaleModel.value,
                onChanged: (NeuralUpscaleModel? value) {
                  if (value != null) {
                    readSetting.saveNeuralUpscaleModel(value);
                  }
                },
                items: NeuralUpscaleModel.values
                    .map((NeuralUpscaleModel model) =>
                        DropdownMenuItem<NeuralUpscaleModel>(
                            value: model, child: Text(model.label)))
                    .toList(),
              ),
            ),
            ListTile(
              title: Text('neuralUpscaleScale'.tr),
              subtitle: Text('neuralUpscaleScaleHint'.tr),
              trailing: DropdownButton<NeuralUpscaleScale>(
                value: scale,
                onChanged: (NeuralUpscaleScale? value) {
                  if (value != null) {
                    readSetting.saveNeuralUpscaleScale(value);
                  }
                },
                items: scaleValues
                    .map((NeuralUpscaleScale scale) =>
                        DropdownMenuItem<NeuralUpscaleScale>(
                            value: scale, child: Text(scale.label)))
                    .toList(),
              ),
            ),
            ListTile(
              title: Text('neuralUpscaleDenoise'.tr),
              subtitle: Text('neuralUpscaleDenoiseHint'.tr),
              trailing: DropdownButton<int>(
                value: denoise,
                onChanged: (int? value) {
                  if (value != null) {
                    readSetting.saveNeuralUpscaleDenoise(value);
                  }
                },
                items: denoiseValues
                    .map((int value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text(value == -1
                              ? 'neuralUpscaleDenoiseNone'.tr
                              : '$value'),
                        ))
                    .toList(),
              ),
            ),
            ListTile(
              title: Text('neuralUpscalePreload'.tr),
              trailing: DropdownButton<int>(
                value: readSetting.neuralUpscalePreload.value,
                onChanged: (int? value) {
                  if (value != null) {
                    readSetting.saveNeuralUpscalePreload(value);
                  }
                },
                items: <int>[0, 1, 2, 3]
                    .map((int value) => DropdownMenuItem<int>(
                        value: value, child: Text('$value')))
                    .toList(),
              ),
            ),
            _buildGpu(),
            const Divider(),
            SwitchListTile(
              title: Text('enableUpscale'.tr),
              subtitle: Text('enableUpscaleHint'.tr),
              value: readSetting.enableNeuralUpscale.isTrue
                  ? false
                  : readSetting.enableUpscale.value,
              onChanged: readSetting.enableNeuralUpscale.isTrue
                  ? null
                  : (bool value) => readSetting.saveEnableUpscale(value),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Text(
                'neuralUpscaleHelp'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildGpu() {
    return ValueListenableBuilder<List<NeuralGpu>>(
      valueListenable: neuralModelManager.gpus,
      builder: (BuildContext context, List<NeuralGpu> gpus, Widget? child) {
        final int current = readSetting.neuralUpscaleGpuId.value;
        final bool currentExists =
            gpus.any((NeuralGpu gpu) => gpu.index == current);
        final int selected = currentExists
            ? current
            : (gpus.isNotEmpty ? gpus.first.index : current);
        final NeuralGpu? selectedGpu = gpus.isEmpty
            ? null
            : gpus.firstWhere(
                (NeuralGpu gpu) => gpu.index == selected,
                orElse: () => gpus.first,
              );

        final String subtitle = gpus.isNotEmpty
            ? selectedGpu!.name
            : (neuralModelManager.isReady
                ? 'neuralUpscaleGpuHintReady'.tr
                : 'neuralUpscaleGpuHint'.tr);

        if (!currentExists && gpus.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (readSetting.neuralUpscaleGpuId.value != gpus.first.index) {
              readSetting.saveNeuralUpscaleGpuId(gpus.first.index);
            }
          });
        }

        return ListTile(
          title: Text('neuralUpscaleGpu'.tr),
          subtitle: Text(subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'neuralUpscaleGpuRefresh'.tr,
                onPressed: () => neuralModelManager.refreshGpus(force: true),
              ),
              DropdownButton<int>(
                value: gpus.isEmpty ? null : selected,
                onChanged: gpus.isEmpty
                    ? null
                    : (int? value) {
                        if (value != null) {
                          readSetting.saveNeuralUpscaleGpuId(value);
                        }
                      },
                items: gpus
                    .map((NeuralGpu gpu) => DropdownMenuItem<int>(
                          value: gpu.index,
                          child: Text('${gpu.index} — ${gpu.name}'),
                        ))
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
