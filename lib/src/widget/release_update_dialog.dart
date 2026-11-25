import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:acervo_hc/src/service/release_update_service.dart';
import 'package:acervo_hc/src/utils/byte_util.dart';
import 'package:acervo_hc/src/utils/route_util.dart';

/// Dialog displaying a newly available GitHub Release with changelog notes,
/// platform-matched download button, and an option to ignore this version.
class ReleaseUpdateDialog extends StatelessWidget {
  final ReleaseUpdateInfo release;
  final String currentVersion;

  const ReleaseUpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
  });

  @override
  Widget build(BuildContext context) {
    final ReleaseAsset? asset = release.selectAssetForPlatform(ReleaseUpdateService.currentPlatformOs());

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update_alt, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('newVersionAvailable'.tr)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'v$currentVersion  →  ${release.tagName}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (asset != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${asset.name} (${byte2String(asset.sizeBytes.toDouble())})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (release.body.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                SelectableText(
                  release.body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await releaseUpdateService.ignoreTag(release.tagName);
            backRoute();
          },
          child: Text('ignoreThisVersion'.tr),
        ),
        TextButton(
          onPressed: backRoute,
          child: Text('cancel'.tr),
        ),
        if (asset != null)
          TextButton(
            onPressed: () => launchUrlString(release.htmlUrl, mode: LaunchMode.externalApplication),
            child: const Text('GitHub'),
          ),
        FilledButton.icon(
          icon: const Icon(Icons.download, size: 18),
          label: Text('download'.tr),
          onPressed: () {
            final String targetUrl = asset?.downloadUrl ?? release.htmlUrl;
            launchUrlString(targetUrl, mode: LaunchMode.externalApplication);
            backRoute();
          },
        ),
      ],
    );
  }
}
