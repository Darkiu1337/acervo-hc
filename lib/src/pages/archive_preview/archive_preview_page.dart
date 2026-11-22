import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/database/database.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/read_page_info.dart';
import 'package:acervo_hc/src/routes/routes.dart';
import 'package:acervo_hc/src/service/archive_download_service.dart';
import 'package:acervo_hc/src/service/read_progress_service.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';
import 'package:acervo_hc/src/utils/byte_util.dart';
import 'package:acervo_hc/src/utils/convert_util.dart';
import 'package:acervo_hc/src/utils/process_util.dart';
import 'package:acervo_hc/src/utils/route_util.dart';
import 'package:acervo_hc/src/widget/eh_image.dart';
import 'package:acervo_hc/src/widget/eh_wheel_speed_controller.dart';
import 'package:acervo_hc/src/widget/icon_text_button.dart';

/// Browses the unpacked page thumbnails of a downloaded archive (`.zip`/`.cbz`)
/// and lets the user jump straight into any page in the reader.
class ArchivePreviewPage extends StatefulWidget {
  const ArchivePreviewPage({Key? key}) : super(key: key);

  @override
  State<ArchivePreviewPage> createState() => _ArchivePreviewPageState();
}

class _ArchivePreviewPageState extends State<ArchivePreviewPage> {
  final ScrollController scrollController = ScrollController();

  late final int? gid = _parseGid(Get.arguments);
  late final ArchiveDownloadedData? archive = gid == null
      ? null
      : archiveDownloadService.archives.firstWhereOrNull((a) => a.gid == gid);

  late Future<List<GalleryImage>> imagesFuture;
  int readIndex = 0;

  @override
  void initState() {
    super.initState();
    imagesFuture = archive == null
        ? Future<List<GalleryImage>>.value(const <GalleryImage>[])
        : archiveDownloadService.getUnpackedImages(archive!.gid);
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    if (archive == null) {
      return;
    }
    final int idx = await readProgressService.getReadProgress(archive!.gid);
    if (mounted) {
      setState(() => readIndex = idx);
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  int? _parseGid(Object? arguments) {
    if (arguments is int) {
      return arguments;
    }
    if (arguments is ArchiveDownloadedData) {
      return arguments.gid;
    }
    return null;
  }

  Future<void> _refresh() async {
    if (archive == null) {
      return;
    }
    setState(() {
      imagesFuture = archiveDownloadService.getUnpackedImages(archive!.gid);
    });
    await _loadProgress();
  }

  Future<void> _openReader(List<GalleryImage> images, int initialIndex) async {
    if (archive == null || images.isEmpty) {
      return;
    }
    if (readSetting.useThirdPartyViewer.isTrue && readSetting.thirdPartyViewerPath.value != null) {
      openThirdPartyViewer(archiveDownloadService.computeArchiveUnpackingPath(archive!));
      return;
    }

    final ReadDirection? readDirection =
        isWebtoonGalleryFromTagString(archive!.tags) ? ReadDirection.top2bottomList : null;

    await toRoute(
      Routes.read,
      arguments: ReadPageInfo(
        mode: ReadMode.archive,
        gid: archive!.gid,
        galleryTitle: archive!.title,
        galleryUrl: archive!.galleryUrl,
        initialIndex: initialIndex.clamp(0, images.length - 1).toInt(),
        pageCount: images.length,
        isOriginal: archive!.isOriginal,
        readProgressRecordStorageKey: archive!.gid.toString(),
        images: images,
        readDirection: readDirection,
      ),
    );
    await _loadProgress();
  }

  @override
  Widget build(BuildContext context) {
    if (archive == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('failed'.tr)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          archive!.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<List<GalleryImage>>(
        future: imagesFuture,
        builder: (BuildContext context, AsyncSnapshot<List<GalleryImage>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<GalleryImage> images = snapshot.data ?? const <GalleryImage>[];
          if (images.isEmpty) {
            return Center(child: Text('noData'.tr));
          }

          return EHWheelSpeedController(
            controller: scrollController,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              scrollBehavior: UIConfig.scrollBehaviourWithScrollBarWithMouse,
              controller: scrollController,
              cacheExtent: 2500,
              slivers: [
                CupertinoSliverRefreshControl(onRefresh: _refresh),
                SliverToBoxAdapter(child: _buildHeader(context, images)),
                const SliverToBoxAdapter(child: Divider(height: 1)),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 170,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.68,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext context, int index) => _buildThumbCard(context, images, index),
                      childCount: images.length,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<GalleryImage> images) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 96,
              height: 136,
              child: EHImage(
                galleryImage: images.first,
                containerWidth: 96,
                containerHeight: 136,
                fit: BoxFit.cover,
                maxBytes: 256 * 1024,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  archive!.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '${images.length} ${'page'.tr}  ·  ${byte2String(archive!.size.toDouble())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openReader(images, readIndex),
                      icon: const Icon(Icons.visibility, size: 18),
                      label: Text(readIndex > 0 ? 'P${readIndex + 1}' : 'read'.tr),
                    ),
                    IconTextButton(
                      icon: const Icon(Icons.folder_open, size: 20),
                      text: Text('open'.tr, style: const TextStyle(fontSize: 12)),
                      onPressed: () => openThirdPartyViewer(archiveDownloadService.computeArchiveUnpackingPath(archive!)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbCard(BuildContext context, List<GalleryImage> images, int index) {
    final bool isCurrent = index == readIndex && readIndex > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openReader(images, index),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: isCurrent
                    ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: EHImage(
                galleryImage: images[index],
                fit: BoxFit.cover,
                maxBytes: 256 * 1024,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isCurrent ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
