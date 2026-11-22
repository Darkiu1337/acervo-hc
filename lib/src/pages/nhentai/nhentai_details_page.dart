import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_thumbnail.dart';
import 'package:acervo_hc/src/model/nhentai_gallery.dart';
import 'package:acervo_hc/src/model/read_page_info.dart';
import 'package:acervo_hc/src/network/nhentai_request.dart';
import 'package:acervo_hc/src/pages/nhentai/nhentai_logic.dart';
import 'package:acervo_hc/src/routes/routes.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/gallery_download/gallery_download_service.dart';
import 'package:acervo_hc/src/service/history_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/read_progress_service.dart';
import 'package:acervo_hc/src/setting/download_setting.dart';
import 'package:acervo_hc/src/setting/site_setting.dart';
import 'package:acervo_hc/src/setting/style_setting.dart';
import 'package:acervo_hc/src/utils/convert_util.dart';
import 'package:acervo_hc/src/utils/route_util.dart';
import 'package:acervo_hc/src/utils/search_util.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/eh_image.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';
import 'package:acervo_hc/src/widget/nhentai_card.dart';
import 'package:acervo_hc/src/widget/nhentai_mark.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Detail page of an external nhentai gallery.
///
/// Opens pages in the shared Acervo H&C reader (with Real-CUGAN/SPAN upscale,
/// Split Wide Pages, and preload), supports multi-tag search/copy, cross-search
/// on E-Hentai, related galleries, local favorites, downloads, and 3-way
/// already-read deduplication.
class NHentaiDetailsPage extends StatefulWidget {
  const NHentaiDetailsPage({Key? key}) : super(key: key);

  @override
  State<NHentaiDetailsPage> createState() => _NHentaiDetailsPageState();
}

class _NHentaiDetailsPageState extends State<NHentaiDetailsPage> {
  late final Gallery gallery = Get.arguments as Gallery;

  NHentaiGalleryDetail? detail;
  List<NHentaiGallerySummary> related = const <NHentaiGallerySummary>[];
  LoadingState loadingState = LoadingState.idle;
  String? errorMessage;
  int? lastReadIndex;

  bool isTagSelectionMode = false;
  final List<NHentaiTag> selectedTags = <NHentaiTag>[];

  int get externalId => gallery.galleryUrl.externalId!;

  bool get _preferJp => SiteSetting.preferJapaneseTitle.isTrue;

  @override
  void initState() {
    super.initState();

    localFavoriteService.ensureRestored();
    alreadyReadService.ensureRestored();

    loadingState = LoadingState.loading;
    _load();
  }

  Future<void> _load() async {
    if (loadingState != LoadingState.loading) {
      setState(() {
        loadingState = LoadingState.loading;
        errorMessage = null;
      });
    }

    try {
      final NHentaiGalleryDetail loaded = await nhentaiRequest.requestDetail(externalId);
      if (!mounted) {
        return;
      }

      setState(() {
        detail = loaded;
        loadingState = LoadingState.success;
      });

      historyService.record(loaded.toHistoryModel(preferJapaneseTitle: _preferJp));

      _loadReadProgress(loaded.pages.length);
      _loadRelated();
    } catch (e, s) {
      log.error('Load nhentai gallery #$externalId failed', e, s);
      if (!mounted) {
        return;
      }

      setState(() {
        loadingState = LoadingState.error;
        errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadReadProgress(int pageCount) async {
    try {
      final int readIndex = await readProgressService.getReadProgress(gallery.galleryUrl.gid);
      if (!mounted) {
        return;
      }
      setState(() {
        lastReadIndex = readIndex > 0 && readIndex < pageCount ? readIndex : null;
      });
    } catch (e) {
      log.error('Load nhentai read progress failed', e);
    }
  }

  Future<void> _loadRelated() async {
    try {
      final List<NHentaiGallerySummary> items = await nhentaiRequest.requestRelated(externalId);
      if (!mounted) {
        return;
      }
      setState(() {
        related = items;
      });
    } catch (e) {
      log.debug('Load nhentai related galleries failed: $e');
    }
  }

  Future<void> _openRead({int? initialIndex}) async {
    final NHentaiGalleryDetail? loaded = detail;
    if (loaded == null || loaded.pages.isEmpty) {
      return;
    }

    final int recordIndex = await readProgressService.getReadProgress(gallery.galleryUrl.gid);

    toRoute(
      Routes.read,
      arguments: ReadPageInfo(
        mode: ReadMode.online,
        gid: gallery.galleryUrl.gid,
        token: gallery.galleryUrl.token,
        galleryTitle: loaded.displayTitle(preferJapaneseTitle: _preferJp),
        galleryUrl: gallery.galleryUrl.url,
        initialIndex: initialIndex ?? (recordIndex < loaded.pages.length ? recordIndex : 0),
        readProgressRecordStorageKey: gallery.galleryUrl.gid.toString(),
        pageCount: loaded.pages.length,
        images: loaded.pages
            .map(
              (NHentaiPageImage p) => GalleryImage(
                url: p.imageUrl,
                width: p.width > 0 ? p.width.toDouble() : null,
                height: p.height > 0 ? p.height.toDouble() : null,
              ),
            )
            .toList(),
        thumbnails: loaded.pages
            .map(
              (NHentaiPageImage p) => GalleryThumbnail(
                href: p.imageUrl,
                isLarge: true,
                thumbUrl: p.thumbUrl,
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _download() async {
    final NHentaiGalleryDetail? loaded = detail;
    if (loaded == null || loaded.pages.isEmpty) {
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
        title: loaded.displayTitle(preferJapaneseTitle: _preferJp),
        category: loaded.categoryLabel,
        pageCount: loaded.pages.length,
        galleryUrl: gallery.galleryUrl.url,
        uploader: <String>[...loaded.artistNames, ...loaded.groupNames].join(', '),
        publishTime: loaded.formattedUploadDate,
        downloadOriginalImage: false,
        group: downloadSetting.defaultGalleryGroup.value ??
            (galleryDownloadService.allGroups.isNotEmpty ? galleryDownloadService.allGroups.first : 'Default'),
        tags: '',
        tagRefreshTime: DateTime.now().toString(),
      ),
    );

    toast('${'beginToDownload'.tr}: ${loaded.displayTitle(preferJapaneseTitle: _preferJp)}', isCenter: false);
  }

  void _searchTagInNHentai(NHentaiTag tag) {
    toRoute(Routes.nhentai);
    final NHentaiLogic logic = Get.isRegistered<NHentaiLogic>()
        ? Get.find<NHentaiLogic>()
        : Get.put<NHentaiLogic>(NHentaiLogic(), permanent: true);
    logic.searchTag(tag);
  }

  void _searchSelectedTagsInNHentai() {
    if (selectedTags.isEmpty) {
      return;
    }
    final String query = selectedTags.map((NHentaiTag t) => t.searchToken).join(' ');
    setState(() {
      isTagSelectionMode = false;
      selectedTags.clear();
    });
    toRoute(Routes.nhentai);
    final NHentaiLogic logic = Get.isRegistered<NHentaiLogic>()
        ? Get.find<NHentaiLogic>()
        : Get.put<NHentaiLogic>(NHentaiLogic(), permanent: true);
    logic.searchQuery(query);
  }

  Future<void> _copySelectedTags() async {
    if (selectedTags.isEmpty) {
      return;
    }
    final String text = selectedTags.map((NHentaiTag t) => t.searchToken).join(' ');
    await Clipboard.setData(ClipboardData(text: text));
    toast('hasCopiedToClipboard'.tr);
    setState(() {
      isTagSelectionMode = false;
      selectedTags.clear();
    });
  }

  void _searchOnEHentai() {
    final NHentaiGalleryDetail? loaded = detail;
    final String rawTitle = loaded != null && loaded.prettyTitle.isNotEmpty
        ? loaded.prettyTitle
        : (loaded?.englishTitle.isNotEmpty == true ? loaded!.englishTitle : gallery.title);
    final String cleaned = rawTitle.replaceAll(RegExp(r'\[.*?\]|\(.*?\)|\{.*?\}'), '').trim();
    if (cleaned.isEmpty) {
      return;
    }
    newSearch(keyword: '"$cleaned"', forceNewRoute: true);
  }

  Future<void> _openInBrowser() async {
    await launchUrlString(gallery.galleryUrl.url, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: gallery.galleryUrl.url));
    toast('copySuccess'.tr);
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: '$externalId'));
    toast('hasCopiedToClipboard'.tr);
  }

  Gallery _snapshotGallery() {
    final NHentaiGalleryDetail? loaded = detail;
    return loaded != null ? loaded.toGallery(preferJapaneseTitle: _preferJp) : gallery;
  }

  GalleryHistoryModel _snapshotHistoryModel() {
    final NHentaiGalleryDetail? loaded = detail;
    return loaded != null ? loaded.toHistoryModel(preferJapaneseTitle: _preferJp) : gallery2GalleryHistoryModel(gallery);
  }

  Future<void> _toggleLocalFavorite() async {
    final bool added = await localFavoriteService.toggle(_snapshotGallery());
    toast(added ? 'localFavoriteAdded'.tr : 'localFavoriteRemoved'.tr);
  }

  Future<void> _toggleAlreadyRead() async {
    final bool added = await alreadyReadService.toggle(_snapshotHistoryModel());
    toast(added ? 'alreadyReadAdded'.tr : 'alreadyReadRemoved'.tr);
  }

  @override
  Widget build(BuildContext context) {
    final String title = detail?.displayTitle(preferJapaneseTitle: _preferJp) ?? gallery.title;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const NHentaiMark(size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
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
            final bool isAlreadyRead = alreadyReadService.isHistoryModelAlreadyRead(_snapshotHistoryModel());
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
            tooltip: 'searchOnEHentai'.tr,
            icon: const Icon(Icons.travel_explore),
            onPressed: _searchOnEHentai,
          ),
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

  Widget _buildBody(BuildContext context) {
    if (loadingState == LoadingState.loading || loadingState == LoadingState.idle) {
      return Center(child: UIConfig.loadingAnimation(context));
    }

    if (loadingState == LoadingState.error || detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(errorMessage ?? 'getGalleryDetailFailed'.tr, textAlign: TextAlign.center),
              const SizedBox(height: 12),
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

    final NHentaiGalleryDetail loaded = detail!;

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
                    containerHeight: 280,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(10),
                    maxBytes: 512 * 1024,
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
        if (related.isNotEmpty) SliverToBoxAdapter(child: _buildRelatedStrip(context)),
        SliverToBoxAdapter(child: _buildPreviewHeader(context, loaded)),
        _buildPreviewGrid(context, loaded),
      ],
    );
  }

  Widget _buildInfo(BuildContext context, NHentaiGalleryDetail loaded) {
    final String primaryTitle = loaded.displayTitle(preferJapaneseTitle: _preferJp);
    final String? secondaryTitle = loaded.alternateTitle(preferJapaneseTitle: _preferJp);

    final List<MapEntry<String, IconData>> sections = <MapEntry<String, IconData>>[
      const MapEntry<String, IconData>('parody', Icons.movie_outlined),
      const MapEntry<String, IconData>('character', Icons.person_outline),
      const MapEntry<String, IconData>('artist', Icons.brush_outlined),
      const MapEntry<String, IconData>('group', Icons.groups_outlined),
      const MapEntry<String, IconData>('language', Icons.translate),
      const MapEntry<String, IconData>('category', Icons.category_outlined),
      const MapEntry<String, IconData>('tag', Icons.local_offer_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(primaryTitle, style: Theme.of(context).textTheme.titleLarge),
        if (secondaryTitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText(
              secondaryTitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: UIConfig.galleryCardTextColor(context)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: const Icon(Icons.tag, size: 15),
                label: Text('#${loaded.id}'),
                visualDensity: VisualDensity.compact,
                onPressed: _copyCode,
              ),
              Text(
                '${loaded.pages.length} ${'pageCount'.tr}',
                style: TextStyle(color: UIConfig.galleryCardTextColor(context)),
              ),
              if (loaded.numFavorites > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, size: 14, color: NHentaiMark.brandColor),
                    const SizedBox(width: 4),
                    Text('${loaded.numFavorites}', style: TextStyle(color: UIConfig.galleryCardTextColor(context))),
                  ],
                ),
              if (loaded.formattedUploadDate.isNotEmpty)
                Text(
                  loaded.formattedUploadDate,
                  style: TextStyle(color: UIConfig.galleryCardTextColor(context)),
                ),
            ],
          ),
        ),
        if (loaded.tags.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isTagSelectionMode)
                  TextButton.icon(
                    onPressed: () => setState(() => isTagSelectionMode = true),
                    icon: const Icon(Icons.checklist, size: 16),
                    label: Text('selectTags'.tr, style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  )
                else ...[
                  TextButton.icon(
                    onPressed: selectedTags.isEmpty ? null : _copySelectedTags,
                    icon: const Icon(Icons.copy, size: 15),
                    label: Text('${'copy'.tr} (${selectedTags.length})', style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                  TextButton.icon(
                    onPressed: selectedTags.isEmpty ? null : _searchSelectedTagsInNHentai,
                    icon: const Icon(Icons.search, size: 15),
                    label: Text('${'search'.tr} (${selectedTags.length})', style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      isTagSelectionMode = false;
                      selectedTags.clear();
                    }),
                    child: Text('cancel'.tr, style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ],
              ],
            ),
          ),
          for (final MapEntry<String, IconData> section in sections)
            if (loaded.tagsOfType(section.key).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: loaded.tagsOfType(section.key).map((NHentaiTag tag) {
                    final bool selected = selectedTags.contains(tag);
                    if (isTagSelectionMode) {
                      return FilterChip(
                        avatar: Icon(section.value, size: 15),
                        label: Text(tag.name),
                        selected: selected,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() {
                            if (selected) {
                              selectedTags.remove(tag);
                            } else {
                              selectedTags.add(tag);
                            }
                          });
                        },
                      );
                    }
                    return ActionChip(
                      avatar: Icon(section.value, size: 15),
                      label: Text(tag.name),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _searchTagInNHentai(tag),
                    );
                  }).toList(),
                ),
              ),
        ],
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
              OutlinedButton.icon(
                onPressed: _searchOnEHentai,
                icon: const Icon(Icons.travel_explore),
                label: Text('searchOnEHentai'.tr),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRelatedStrip(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('relatedGalleries'.tr, style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: related.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int index) {
              final NHentaiGallerySummary item = related[index];
              final Gallery relGallery = item.toGallery(preferJapaneseTitle: _preferJp);
              return SizedBox(
                width: 130,
                child: NHentaiCard(
                  gallery: relGallery,
                  numFavorites: item.numFavorites,
                  onTap: () => toRoute(
                    Routes.nhentaiDetails,
                    arguments: relGallery,
                    preventDuplicates: false,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewHeader(BuildContext context, NHentaiGalleryDetail loaded) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Text('preview'.tr, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text(
            '${loaded.pages.length} ${'pageCount'.tr}',
            style: TextStyle(color: UIConfig.galleryCardTextColor(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewGrid(BuildContext context, NHentaiGalleryDetail loaded) {
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
          childCount: loaded.pages.length,
        ),
      ),
    );
  }

  Widget _buildPreviewCell(BuildContext context, NHentaiGalleryDetail loaded, int index) {
    final bool isLastRead = lastReadIndex == index;
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final NHentaiPageImage page = loaded.pages[index];

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
                galleryImage: GalleryImage(url: page.thumbUrl),
                autoLayout: true,
                fit: BoxFit.contain,
                containerColor: UIConfig.galleryCardBackGroundColor(context),
                borderRadius: BorderRadius.circular(8),
                maxBytes: 384 * 1024,
                loadingWidgetBuilder: () => const SizedBox.shrink(),
                failedWidgetBuilder: (_) => EHImage(
                  galleryImage: GalleryImage(url: page.imageUrl),
                  autoLayout: true,
                  fit: BoxFit.contain,
                  containerColor: UIConfig.galleryCardBackGroundColor(context),
                  borderRadius: BorderRadius.circular(8),
                  maxBytes: 384 * 1024,
                  loadingWidgetBuilder: () => const SizedBox.shrink(),
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
}
