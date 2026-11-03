import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/service/image_viewer_scanner_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:path/path.dart' as p;

/// Result of [ImageViewerSelectDialog].
///
/// An empty [path] means "do not use an external viewer".
class ImageViewerSelection {
  const ImageViewerSelection({required this.name, required this.path});

  final String name;
  final String path;

  bool get isEmpty => path.isEmpty;
}

/// Lists the image viewers installed on the machine and lets the user pick
/// one, including packaged Store apps that do not expose a browsable .exe.
class ImageViewerSelectDialog extends StatefulWidget {
  const ImageViewerSelectDialog({super.key, this.currentPath});

  final String? currentPath;

  @override
  State<ImageViewerSelectDialog> createState() => _ImageViewerSelectDialogState();
}

class _ImageViewerSelectDialogState extends State<ImageViewerSelectDialog> {
  List<ImageViewerEntry> _viewers = const <ImageViewerEntry>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _loading = true);
    final List<ImageViewerEntry> viewers = await imageViewerScannerService.scan();
    if (!mounted) {
      return;
    }
    setState(() {
      _viewers = viewers;
      _loading = false;
    });
  }

  Future<void> _browse() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles();
    } on Exception catch (e) {
      log.error('Pick external viewer failed', e);
    }

    final String? path = result?.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(ImageViewerSelection(name: p.basenameWithoutExtension(path), path: path));
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final double width = min(screen.width * 0.92, 580.0);
    final double height = min(screen.height * 0.85, 640.0);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('selectImageViewer'.tr, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text('selectImageViewerHint'.tr, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text('selectImageViewerScanning'.tr),
                        ],
                      ),
                    )
                  : _viewers.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('selectImageViewerEmpty'.tr, textAlign: TextAlign.center),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _viewers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (BuildContext context, int index) {
                            final ImageViewerEntry viewer = _viewers[index];
                            final bool isCurrent = widget.currentPath != null && p.equals(widget.currentPath!, viewer.path);
                            return ListTile(
                              leading: Icon(viewer.isStoreApp ? Icons.storefront_outlined : Icons.image_outlined),
                              title: Text(viewer.name),
                              subtitle: Text(viewer.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: isCurrent
                                  ? Chip(
                                      label: Text('selectImageViewerCurrent'.tr),
                                    )
                                  : viewer.isStoreApp
                                      ? Text('selectImageViewerStore'.tr, style: Theme.of(context).textTheme.bodySmall)
                                      : null,
                              onTap: () => Navigator.of(context).pop(ImageViewerSelection(name: viewer.name, path: viewer.path)),
                            );
                          },
                        ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text('selectImageViewerBrowse'.tr),
              onTap: _browse,
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text('selectImageViewerClear'.tr),
              onTap: () => Navigator.of(context).pop(const ImageViewerSelection(name: '', path: '')),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                'selectImageViewerStoreHint'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
