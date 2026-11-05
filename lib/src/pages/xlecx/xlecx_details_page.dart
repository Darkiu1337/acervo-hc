import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_thumbnail.dart';
import 'package:acervo_hc/src/model/read_page_info.dart';
import 'package:acervo_hc/src/model/xlecx_detail.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/network/xlecx_request.dart';
import 'package:acervo_hc/src/pages/xlecx/xlecx_logic.dart';
import 'package:acervo_hc/src/routes/routes.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/gallery_download/gallery_download_service.dart';
import 'package:acervo_hc/src/service/history_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/read_progress_service.dart';
import 'package:acervo_hc/src/setting/download_setting.dart';
import 'package:acervo_hc/src/setting/style_setting.dart';
import 'package:acervo_hc/src/utils/convert_util.dart';
import 'package:acervo_hc/src/utils/route_util.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/utils/xlecx_parser.dart';
import 'package:acervo_hc/src/widget/eh_image.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';
import 'package:acervo_hc/src/widget/xlecx_account_dialog.dart';
import 'package:acervo_hc/src/widget/xlecx_mark.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Detail page of an external (Xlecx) gallery.
///
/// Kept separate from [DetailsPageLogic] on purpose: the E-H detail page owns
/// rating, favorites, torrents, archives, comments and thumbnails paging, none
/// of which exist on the external source. The page list is fully resolved by
/// the post itself, so the reader never parses E-H pages.
class XlecxDetailsPage extends StatefulWidget {
  const XlecxDetailsPage({Key? key}) : super(key: key);

  @override
  State<XlecxDetailsPage> createState() => _XlecxDetailsPageState();
}

class _XlecxDetailsPageState extends State<XlecxDetailsPage> {
  late final Gallery gallery = Get.arguments as Gallery;

  XlecxDetail? detail;
  LoadingState loadingState = LoadingState.idle;
  String? errorMessage;

  /// Marker of a refused page ([XlecxRequest.restrictedErrorMarker] and
  /// friends), used to pick a message and to hide a useless retry button.
  String? errorMarker;

  /// Page the reader will resume at, highlighted in the preview grid.
  int? lastReadIndex;

  int get externalId => gallery.galleryUrl.externalId!;

  @override
  void initState() {
    super.initState();

    localFavoriteService.ensureRestored();
    alreadyReadService.ensureRestored();

    /// Set before the first build: calling setState from initState would run
    /// while the framework is still building the parent.
    loadingState = LoadingState.loading;
    _load();
  }

  Future<void> _load() async {
    if (loadingState != LoadingState.loading) {
      setState(() {
        loadingState = LoadingState.loading;
        errorMessage = null;
        errorMarker = null;
      });
    }

    try {
      final XlecxDetail loaded = await xlecxRequest.requestDetail(gallery.galleryUrl);
      if (!mounted) {
        return;
      }

      setState(() {
        detail = loaded;
        loadingState = LoadingState.success;
      });

      historyService.record(
        GalleryHistoryModel(
          galleryUrl: gallery.galleryUrl,
          title: loaded.title,
          category: XlecxParser.categoryLabel,
          coverUrl: loaded.coverUrl,
          pageCount: loaded.pageCount,
          rating: gallery.rating,
          language: 'EN',
          uploader: loaded.artistLabels.join(', '),
          publishTime: loaded.publishTime,
          isExpunged: false,
          tags: loaded.tagLabels,
        ),
      );

      try {
        final int readIndex = await readProgressService.getReadProgress(gallery.galleryUrl.gid);
        if (!mounted) {
          return;
        }

        setState(() {
          lastReadIndex = readIndex > 0 && readIndex < loaded.pageCount ? readIndex : null;
        });
      } catch (e) {
        log.error('Load Xlecx read progress failed', e);
      }
    } catch (e, s) {
      log.error('Load Xlecx gallery #$externalId failed', e, s);
      if (!mounted) {
        return;
      }

      setState(() {
        loadingState = LoadingState.error;
        errorMarker = XlecxRequest.errorMarkerOf(e);
        errorMessage = e.toString();
      });
    }
  }

  /// Both lists are already resolved by the post, so the reader receives the
  /// full size images and their thumbnails directly.
  Future<void> _openRead({int? initialIndex}) async {
    final XlecxDetail? loaded = detail;
    if (loaded == null) {
      return;
    }

    final int recordIndex = await readProgressService.getReadProgress(gallery.galleryUrl.gid);

    toRoute(
      Routes.read,
      arguments: ReadPageInfo(
        mode: ReadMode.online,
        gid: gallery.galleryUrl.gid,
        token: gallery.galleryUrl.token,
        galleryTitle: loaded.title,
        galleryUrl: gallery.galleryUrl.url,
        initialIndex: initialIndex ?? (recordIndex < loaded.pageCount ? recordIndex : 0),
        readProgressRecordStorageKey: gallery.galleryUrl.gid.toString(),
        pageCount: loaded.pageCount,
        images: _images(loaded),
        thumbnails: _thumbnails(loaded),
      ),
    );
  }

  List<GalleryImage> _images(XlecxDetail loaded) {
    return loaded.pageUrls.map((String url) => GalleryImage(url: url)).toList();
  }

  List<GalleryThumbnail> _thumbnails(XlecxDetail loaded) {
    return List<GalleryThumbnail>.generate(
      loaded.pageCount,
      (int index) => GalleryThumbnail(
        href: loaded.pageUrls[index],
        isLarge: true,
        thumbUrl: loaded.thumbUrls[index],
      ),
    );
  }

  Future<void> _download() async {
    final XlecxDetail? loaded = detail;
    if (loaded == null) {
      return;
    }

    if (galleryDownloadService.containGallery(gallery.galleryUrl.gid)) {
      toast('downloaded'.tr);
      return;
    }

    galleryDownloadService.downloadGallery(
      GalleryDownloadRequest(
        gid: gallery.galleryUrl.gid,
        token: gallery.galleryUrl.token,
        title: loaded.title,
        category: XlecxParser.categoryLabel,
        pageCount: loaded.pageCount,
        galleryUrl: gallery.galleryUrl.url,
        uploader: loaded.artistLabels.join(', '),
        publishTime: loaded.publishTime,
        downloadOriginalImage: false,
        group: downloadSetting.defaultGalleryGroup.value ??
            (galleryDownloadService.allGroups.isNotEmpty ? galleryDownloadService.allGroups.first : 'Default'),
        tags: '',
        tagRefreshTime: DateTime.now().toString(),
      ),
    );

    toast('${'beginToDownload'.tr}: ${loaded.title}', isCenter: false);
  }

  /// Opens the Xlecx tab filtered by [tag]. On desktop the results show up in
  /// the left column while this page stays on the right.
  void _searchTag(XlecxTag tag) {
    toRoute(Routes.xlecx);

    final XlecxLogic logic = Get.isRegistered<XlecxLogic>()
        ? Get.find<XlecxLogic>()
        : Get.put<XlecxLogic>(XlecxLogic(), permanent: true);

    logic.searchTag(tag);
  }

  void _searchCategory(XlecxCategory category) {
    toRoute(Routes.xlecx);

    final XlecxLogic logic = Get.isRegistered<XlecxLogic>()
        ? Get.find<XlecxLogic>()
        : Get.put<XlecxLogic>(XlecxLogic(), permanent: true);

    logic.setCategory(category);
  }

  Future<void> _openInBrowser() async {
    await launchUrlString(gallery.galleryUrl.url, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: gallery.galleryUrl.url));
    toast('copySuccess'.tr);
  }

  /// Best snapshot available: the post holds more metadata than the listing
  /// card, so refresh the stored copy whenever it is loaded.
  Gallery _favoriteSnapshot() {
    final XlecxDetail? loaded = detail;
    if (loaded == null) {
      return gallery;
    }

    return gallery.copyWith(
      title: loaded.title,
      pageCount: loaded.pageCount,
      uploader: loaded.artistLabels.isEmpty ? gallery.uploader : loaded.artistLabels.join(', '),
      publishTime: loaded.publishTime,
      externalTags: loaded.tagLabels,
      language: 'EN',
    );
  }

  Future<void> _toggleLocalFavorite() async {
    final bool added = await localFavoriteService.toggle(_favoriteSnapshot());
    toast(added ? 'localFavoriteAdded'.tr : 'localFavoriteRemoved'.tr);
  }

  Future<void> _toggleAlreadyRead() async {
    final bool added = await alreadyReadService.toggle(gallery2GalleryHistoryModel(_favoriteSnapshot()));
    toast(added ? 'alreadyReadAdded'.tr : 'alreadyReadRemoved'.tr);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const XlecxMark(size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detail?.title ?? gallery.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Obx(() {
            final bool isFavorite = localFavoriteService.contains(gallery.gid);
            return IconButton(
              tooltip: isFavorite ? 'removeFromLocalFavorites'.tr : 'addToLocalFavorites'.tr,
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? Colors.redAccent : null,
              ),
              onPressed: _toggleLocalFavorite,
            );
          }),
          Obx(() {
            final bool isAlreadyRead = alreadyReadService.contains(gallery.gid);
            return IconButton(
              tooltip: isAlreadyRead ? 'removeFromAlreadyRead'.tr : 'markAsAlreadyRead'.tr,
              icon: Icon(
                isAlreadyRead ? Icons.check_circle : Icons.check_circle_outline,
                color: isAlreadyRead ? Theme.of(context).colorScheme.primary : null,
              ),
              onPressed: _toggleAlreadyRead,
            );
          }),
          IconButton(
            tooltip: 'openInBrowser'.tr,
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInBrowser,
          ),
          IconButton(
            tooltip: 'copyLink'.tr,
            icon: const Icon(Icons.link),
            onPressed: _copyLink,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  /// Message shown on the error state: the refused-page markers get a
  /// translated explanation, anything else keeps the raw error.
  String get _errorText => switch (errorMarker) {
        XlecxRequest.restrictedErrorMarker => 'xlecxRestricted'.tr,
        XlecxRequest.notFoundErrorMarker => 'xlecxNotFound'.tr,
        XlecxRequest.cloudflareErrorMarker => 'xlecxBlocked'.tr,
        _ => errorMessage ?? 'getGalleryDetailFailed'.tr,
      };

  Widget _buildBody(BuildContext context) {
    if (loadingState == LoadingState.loading || loadingState == LoadingState.idle) {
      return Center(child: UIConfig.loadingAnimation(context));
    }

    if (loadingState == LoadingState.error || detail == null) {
      final bool isPermanent = errorMarker == XlecxRequest.restrictedErrorMarker || errorMarker == XlecxRequest.notFoundErrorMarker;

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isPermanent ? Icons.lock_outline : Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(_errorText, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (isPermanent)
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _openInBrowser,
                      icon: const Icon(Icons.open_in_browser),
                      label: Text('openInBrowser'.tr),
                    ),
                    if (errorMarker == XlecxRequest.restrictedErrorMarker)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final bool saved = await showXlecxAccountDialog(context);
                          if (saved) {
                            await _load();
                          }
                        },
                        icon: const Icon(Icons.account_circle_outlined),
                        label: Text('xlecxAccountSetup'.tr),
                      ),
                  ],
                )
              else
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: Text('retry'.tr),
                ),
            ],
          ),
        ),
      );
    }

    final XlecxDetail loaded = detail!;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget cover = ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: EHImage(
                    galleryImage: GalleryImage(url: loaded.coverUrl.isEmpty ? gallery.cover.url : loaded.coverUrl),
                    containerWidth: 200,
                    containerHeight: 267,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(10),
                  ),
                );

                final Widget info = _buildInfo(context, loaded);

                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: cover),
                      const SizedBox(height: 16),
                      info,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cover,
                    const SizedBox(width: 16),
                    Expanded(child: info),
                  ],
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(child: _buildPreviewHeader(context, loaded)),
        _buildPreviewGrid(context, loaded),
      ],
    );
  }

  Widget _buildPreviewHeader(BuildContext context, XlecxDetail loaded) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Text('preview'.tr, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text(
            '${loaded.pageCount} ${'pageCount'.tr}',
            style: TextStyle(color: UIConfig.galleryCardTextColor(context)),
          ),
        ],
      ),
    );
  }

  /// Thumbnail grid of every page. Tapping a cell opens the reader at that
  /// page. [SliverGrid] builds the cells lazily, so only the visible thumbnails
  /// are requested.
  Widget _buildPreviewGrid(BuildContext context, XlecxDetail loaded) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 200),
      sliver: SliverGrid(
        gridDelegate: styleSetting.crossAxisCountInDetailPage.value == null
            ? const SliverGridDelegateWithMaxCrossAxisExtent(
                mainAxisExtent: UIConfig.detailsPageThumbnailHeight,
                maxCrossAxisExtent: UIConfig.detailsPageThumbnailWidth,
                mainAxisSpacing: 20,
                crossAxisSpacing: 5,
              )
            : SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: styleSetting.crossAxisCountInDetailPage.value!,
                mainAxisSpacing: 20,
                crossAxisSpacing: 5,
                childAspectRatio: UIConfig.detailsPageGridViewCardAspectRatio,
              ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) => _buildPreviewCell(context, loaded, index),
          childCount: loaded.pageCount,
        ),
      ),
    );
  }

  Widget _buildPreviewCell(BuildContext context, XlecxDetail loaded, int index) {
    final bool isLastRead = lastReadIndex == index;
    final Color primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _openRead(initialIndex: index),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: isLastRead ? Border.all(color: primaryColor, width: 2) : null,
              ),
              child: EHImage(
                galleryImage: GalleryImage(url: loaded.thumbUrls[index]),
                autoLayout: true,
                fit: BoxFit.contain,
                containerColor: UIConfig.galleryCardBackGroundColor(context),
                borderRadius: BorderRadius.circular(8),
                maxBytes: 512 * 1024,

                /// Fall back to the full size image instead of leaving a broken
                /// tile when the thumbnail route fails.
                failedWidgetBuilder: (_) => EHImage(
                  galleryImage: GalleryImage(url: loaded.pageUrls[index]),
                  autoLayout: true,
                  fit: BoxFit.contain,
                  containerColor: UIConfig.galleryCardBackGroundColor(context),
                  borderRadius: BorderRadius.circular(8),
                  maxBytes: 512 * 1024,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${index + 1}',
          style: TextStyle(
            color: isLastRead ? primaryColor : UIConfig.detailsPageThumbnailIndexColor(context),
          ),
        ),
      ],
    );
  }

  Widget _buildInfo(BuildContext context, XlecxDetail loaded) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loaded.title, style: Theme.of(context).textTheme.titleLarge),
        if (loaded.artistLabels.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${'author'.tr}: ${loaded.artistLabels.join(', ')}',
              style: TextStyle(color: UIConfig.galleryCardTextColor(context)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${loaded.pageCount} ${'pageCount'.tr}', style: TextStyle(color: UIConfig.galleryCardTextColor(context))),
        ),
        if (loaded.categories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: loaded.categories
                  .map(
                    (XlecxCategory category) => ActionChip(
                      avatar: const Icon(Icons.category_outlined, size: 16),
                      label: Text(category.label),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _searchCategory(category),
                    ),
                  )
                  .toList(),
            ),
          ),
        if (loaded.parodies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: loaded.parodies
                  .map(
                    (XlecxTag parody) => ActionChip(
                      avatar: const Icon(Icons.movie_outlined, size: 16),
                      label: Text(parody.label),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _searchTag(parody),
                    ),
                  )
                  .toList(),
            ),
          ),
        if (loaded.groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: loaded.groups
                  .map(
                    (XlecxTag group) => ActionChip(
                      avatar: const Icon(Icons.groups_outlined, size: 16),
                      label: Text(group.label),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _searchTag(group),
                    ),
                  )
                  .toList(),
            ),
          ),
        if (loaded.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: loaded.tags
                  .map(
                    (XlecxTag tag) => ActionChip(
                      label: Text(tag.label),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _searchTag(tag),
                    ),
                  )
                  .toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _openRead,
                icon: const Icon(Icons.menu_book),
                label: Text('read'.tr),
              ),
              OutlinedButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download),
                label: Text('download'.tr),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
