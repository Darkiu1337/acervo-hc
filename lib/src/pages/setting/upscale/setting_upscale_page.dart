import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:acervo_hc/src/model/neural_gpu.dart';
import 'package:acervo_hc/src/model/neural_upscale_config.dart';
import 'package:acervo_hc/src/service/neural_model_manager.dart';
import 'package:acervo_hc/src/service/neural_upscale_service.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';

/// All image-enhancement settings in one place: the on-demand neural upscaler
/// (model, scale, denoise, preload, GPU) and the managed model installs.
class SettingUpscalePage extends StatelessWidget {
  const SettingUpscalePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text('upscale'.tr)),
      body: Obx(() {
        neuralModelManager.init();
        final NeuralUpscaleModel selectedModel =
            readSetting.neuralUpscaleModel.value;
        final bool proModel = selectedModel == NeuralUpscaleModel.pro;
        final List<int> denoiseValues =
            proModel ? <int>[-1, 0, 3] : <int>[-1, 0, 1, 2, 3];
        final int denoise =
            denoiseValues.contains(readSetting.neuralUpscaleDenoise.value)
                ? readSetting.neuralUpscaleDenoise.value
                : 0;
        final int maxScale = selectedModel.maxScale;
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
                  final bool ready = await neuralModelManager
                      .ensureModelReady(readSetting.neuralUpscaleModel.value);
                  if (!ready) {
                    toast('neuralUpscaleDownloadFailed'.tr);
                    return;
                  }
                }
                readSetting.saveEnableNeuralUpscale(value);
              },
            ),
            _buildModelStatus(selectedModel),
            ValueListenableBuilder<int>(
              valueListenable: neuralModelManager.revision,
              builder: (BuildContext context, int _, Widget? child) {
                return ListTile(
                  title: Text('neuralUpscaleModel'.tr),
                  subtitle: Text(selectedModel.descriptionKey.tr),
                  trailing: DropdownButton<NeuralUpscaleModel>(
                    value: selectedModel,
                    onChanged: (NeuralUpscaleModel? value) async {
                      if (value == null || value == selectedModel) {
                        return;
                      }
                      await readSetting.saveNeuralUpscaleModel(value);
                      if (readSetting.enableNeuralUpscale.value &&
                          !neuralModelManager.isModelReady(value)) {
                        final bool ok =
                            await neuralModelManager.ensureModelReady(value);
                        if (ok) {
                          neuralUpscaleService.refreshSession();
                        } else {
                          toast('neuralUpscaleDownloadFailed'.tr);
                        }
                      }
                    },
                    items: NeuralUpscaleModel.values
                        .map((NeuralUpscaleModel model) {
                      final bool installed =
                          neuralModelManager.isModelReady(model);
                      return DropdownMenuItem<NeuralUpscaleModel>(
                        value: model,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(model.label),
                            if (installed) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green,
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
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
            if (selectedModel.supportsDenoise)
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
              subtitle: Text('neuralUpscalePreloadHint'.tr),
              trailing: DropdownButton<int>(
                value: readSetting.neuralUpscalePreload.value,
                onChanged: (int? value) {
                  if (value != null) {
                    readSetting.saveNeuralUpscalePreload(value);
                  }
                },
                items: <int>[0, 1, 2, 3, 4, 5, 6, 7, 8]
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
              value: readSetting.enableUpscale.value,
              onChanged: (bool value) => readSetting.saveEnableUpscale(value),
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

  Widget _buildModelStatus(NeuralUpscaleModel selectedModel) {
    return ValueListenableBuilder<int>(
      valueListenable: neuralModelManager.revision,
      builder: (BuildContext context, int _, Widget? child) {
        return ValueListenableBuilder<NeuralModelStatus>(
          valueListenable: neuralModelManager.status,
          builder: (BuildContext context, NeuralModelStatus _, Widget? child) {
            final NeuralModelStatus modelStatus =
                neuralModelManager.statusFor(selectedModel);
            final NeuralUpscaleModel? activeDownload =
                neuralModelManager.downloadingModel.value;

            if (modelStatus == NeuralModelStatus.ready) {
              neuralModelManager.refreshGpus();
              return ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text('neuralUpscaleModelReady'.tr),
                subtitle: Text(
                  '${selectedModel.label} — ${selectedModel.descriptionKey.tr}',
                ),
              );
            }
            if (modelStatus == NeuralModelStatus.downloading ||
                (neuralModelManager.status.value ==
                        NeuralModelStatus.downloading &&
                    activeDownload != null)) {
              final String targetLabel =
                  activeDownload?.label ?? selectedModel.label;
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
                    title: Text('${'neuralUpscaleDownloading'.tr} ($targetLabel)'),
                    subtitle: LinearProgressIndicator(value: progress),
                  );
                },
              );
            }
            return ListTile(
              leading: const Icon(Icons.download),
              title: Text('neuralUpscaleDownloadModel'.tr),
              subtitle: Text(
                '${selectedModel.label} (${selectedModel.downloadSizeHint}) — ${selectedModel.descriptionKey.tr}',
              ),
              trailing: TextButton(
                onPressed: () async {
                  final bool ok = await neuralModelManager
                      .ensureModelReady(selectedModel);
                  if (ok) {
                    neuralUpscaleService.refreshSession();
                  } else {
                    toast('neuralUpscaleDownloadFailed'.tr);
                  }
                },
                child: Text('download'.tr),
              ),
            );
          },
        );
      },
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
            : (neuralModelManager.isAnyReady
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
