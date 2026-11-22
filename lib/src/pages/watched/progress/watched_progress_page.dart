import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/service/watched_progress_service.dart';
import 'package:acervo_hc/src/utils/date_util.dart';
import 'package:acervo_hc/src/widget/eh_alert_dialog.dart';

/// Displays where the user left off in the Watched list, saved Watched
/// bookmarks, and seen-gallery stats, allowing one-tap jumps back into Watched.
class WatchedProgressPage extends StatelessWidget {
  final ValueChanged<int>? onJumpToGid;

  const WatchedProgressPage({
    Key? key,
    this.onJumpToGid,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    watchedProgressService.ensureLoaded();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('watchedProgress'.tr),
        actions: [
          IconButton(
            tooltip: 'clear'.tr,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final bool? ok = await Get.dialog(
                EHDialog(title: '${'clear'.tr}?'),
              );
              if (ok == true) {
                await watchedProgressService.clearAll();
              }
            },
          ),
        ],
      ),
      body: Obx(() {
        // Subscribe to revision updates.
        watchedProgressService.revision.value;

        final WatchedBookmark? anchor = watchedProgressService.lastAnchor;
        final List<WatchedBookmark> bookmarks = watchedProgressService.bookmarks;
        final int seenCount = watchedProgressService.seenCount;

        if (anchor == null && bookmarks.isEmpty && seenCount == 0) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'watchedProgressEmpty'.tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text('watchedSeenCount'.tr),
                trailing: Text(
                  '$seenCount',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            if (anchor != null) ...[
              const SizedBox(height: 16),
              Text('watchedLastPosition'.tr, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.play_arrow_rounded),
                  title: Text(anchor.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '#${anchor.gid}  ·  ${DateUtil.transformUtc2LocalTimeString(DateTime.fromMillisecondsSinceEpoch(anchor.createdAtMs, isUtc: true).toIso8601String())}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    onJumpToGid?.call(anchor.gid);
                  },
                ),
              ),
            ],
            if (bookmarks.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('watchedBookmarks'.tr, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...bookmarks.map(
                (WatchedBookmark bm) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.bookmark_outline),
                    title: Text(bm.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('#${bm.gid}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => watchedProgressService.removeBookmark(bm.gid),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      onJumpToGid?.call(bm.gid);
                    },
                  ),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }
}
