import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/service/external_viewer_service.dart';

/// Small non-blocking indicator shown while a gallery is being prepared for
/// the external image viewer. It stays visible during the background download
/// and disappears when the work is done.
class ExternalViewerProgressOverlay extends StatelessWidget {
  const ExternalViewerProgressOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ExternalViewerProgress? progress = externalViewerService.progress.value;
      if (progress == null) {
        return const SizedBox.shrink();
      }

      return Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        right: 12,
        child: Material(
          color: const Color(0xE6000000),
          borderRadius: BorderRadius.circular(12),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress.stage == ExternalViewerStage.downloading && progress.total > 0 ? progress.done / progress.total : null,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(progress),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      if (progress.done > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${progress.done}/${progress.total} · ${formatFileSize(progress.bytes)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                      if (progress.stage == ExternalViewerStage.downloading) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress.total > 0 ? progress.done / progress.total : null,
                            minHeight: 4,
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (progress.cancellable) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'externalViewerCancelDownload'.tr,
                    onPressed: externalViewerService.cancelDownload,
                    icon: const Icon(Icons.close, size: 16, color: Colors.white70),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  String _title(ExternalViewerProgress progress) {
    switch (progress.stage) {
      case ExternalViewerStage.preparing:
        return 'externalViewerPreparing'.tr;
      case ExternalViewerStage.downloading:
        return 'externalViewerDownloading'.tr;
      case ExternalViewerStage.opening:
        return 'externalViewerOpening'.tr;
    }
  }
}
