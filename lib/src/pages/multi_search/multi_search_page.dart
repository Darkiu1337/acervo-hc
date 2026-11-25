import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/pages/details/details_page_logic.dart';
import 'package:acervo_hc/src/pages/multi_search/multi_search_logic.dart';
import 'package:acervo_hc/src/pages/multi_search/multi_search_state.dart';
import 'package:acervo_hc/src/routes/routes.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/utils/convert_util.dart';
import 'package:acervo_hc/src/utils/route_util.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/eh_context_menu.dart';
import 'package:acervo_hc/src/widget/eh_image.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

/// Unified parallel search across E-Hentai/ExHentai, Xlecx, and nhentai with
/// cross-provider equivalence indicators and Already Read filtering.
class MultiSearchPage extends StatelessWidget {
  const MultiSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final MultiSearchLogic logic = Get.put<MultiSearchLogic>(MultiSearchLogic());

    return Scaffold(
      appBar: AppBar(
        title: Text('multiSourceSearch'.tr),
        centerTitle: false,
      ),
      body: Column(
        children: [
          GetBuilder<MultiSearchLogic>(
            id: logic.headerId,
            builder: (_) => _buildHeader(context, logic),
          ),
          Expanded(
            child: GetBuilder<MultiSearchLogic>(
              id: logic.bodyId,
              builder: (_) => _buildBody(context, logic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, MultiSearchLogic logic) {
    final MultiSearchState state = logic.state;
    final int totalVisible = logic.visibleCombinedGalleries().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: state.searchController,
                  focusNode: state.searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: logic.submitSearch,
                  decoration: InputDecoration(
                    hintText: 'multiSourceSearchHint'.tr,
                    prefixIcon: const Icon(Icons.travel_explore, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: state.searchController.text.isNotEmpty || state.query.isNotEmpty
                        ? IconButton(
                            tooltip: 'clear'.tr,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: logic.clearSearch,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.search, size: 18),
                label: Text('search'.tr),
                onPressed: () => logic.submitSearch(state.searchController.text),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final GallerySource source in GallerySource.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(_sourceLabel(source)),
                      selected: state.enabledSources.contains(source),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => logic.toggleSourceEnabled(source),
                    ),
                  ),
                const SizedBox(width: 6),
                FilterChip(
                  avatar: Icon(
                    state.hideAlreadyRead ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 16,
                  ),
                  label: Text('hideAlreadyRead'.tr),
                  selected: state.hideAlreadyRead,
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                  onSelected: (_) => logic.toggleHideAlreadyRead(),
                ),
              ],
            ),
          ),
          if (state.hasSearched) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('${'all'.tr} ($totalVisible)'),
                    selected: state.activeTab == null,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => logic.selectTab(null),
                  ),
                  const SizedBox(width: 6),
                  for (final GallerySource source in GallerySource.values)
                    if (state.enabledSources.contains(source))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _buildSourceTabChip(context, logic, source),
                      ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceTabChip(BuildContext context, MultiSearchLogic logic, GallerySource source) {
    final SourceSearchBucket bucket = logic.state.buckets[source]!;
    final int count = logic.visibleGalleriesFor(source).length;

    Widget? avatar;
    if (bucket.loadingState == LoadingState.loading) {
      avatar = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (bucket.loadingState == LoadingState.error) {
      avatar = Icon(Icons.error_outline, size: 16, color: UIConfig.alertColor(context));
    }

    return ChoiceChip(
      avatar: avatar,
      label: Text('${_sourceLabel(source)} ($count)'),
      selected: logic.state.activeTab == source,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => logic.selectTab(source),
    );
  }

  Widget _buildBody(BuildContext context, MultiSearchLogic logic) {
    final MultiSearchState state = logic.state;
    if (!state.hasSearched) {
      final Color hintColor = UIConfig.galleryCardTextColor(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.travel_explore, size: 56, color: hintColor),
              const SizedBox(height: 12),
              Text('multiSourceSearch'.tr, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('multiSourceSearchEmptyHint'.tr, textAlign: TextAlign.center, style: TextStyle(color: hintColor)),
            ],
          ),
        ),
      );
    }

    final GallerySource? activeTab = state.activeTab;
    if (activeTab != null) {
      final SourceSearchBucket bucket = state.buckets[activeTab]!;
      final List<Gallery> items = logic.visibleGalleriesFor(activeTab);

      if (bucket.loadingState == LoadingState.loading && items.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (bucket.loadingState == LoadingState.error && items.isEmpty) {
        return _buildErrorState(context, activeTab, bucket.errorMessage, () => logic.retrySource(activeTab));
      }
      if (items.isEmpty) {
        return Center(child: Text('noData'.tr));
      }

      return _buildGrid(
        context,
        logic,
        items: items,
        footer: bucket.hasMore
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: bucket.loadingState == LoadingState.loading
                      ? const CircularProgressIndicator()
                      : OutlinedButton(
                          onPressed: () => logic.loadMoreForSource(activeTab),
                          child: Text('loadMore'.tr),
                        ),
                ),
              )
            : null,
      );
    }

    final List<Gallery> combined = logic.visibleCombinedGalleries();
    final bool anyLoading = state.enabledSources.any(
      (GallerySource s) => state.buckets[s]!.loadingState == LoadingState.loading,
    );
    final List<GallerySource> erroredSources = state.enabledSources
        .where((GallerySource s) => state.buckets[s]!.loadingState == LoadingState.error)
        .toList();

    if (combined.isEmpty && anyLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        if (erroredSources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: erroredSources
                  .map(
                    (GallerySource s) => ActionChip(
                      avatar: Icon(Icons.refresh, size: 16, color: UIConfig.alertColor(context)),
                      label: Text('${_sourceLabel(s)}: ${'retry'.tr}'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => logic.retrySource(s),
                    ),
                  )
                  .toList(),
            ),
          ),
        Expanded(
          child: combined.isEmpty
              ? Center(child: Text('noData'.tr))
              : _buildGrid(context, logic, items: combined),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, GallerySource source, String? message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 42, color: UIConfig.alertColor(context)),
            const SizedBox(height: 10),
            Text('${_sourceLabel(source)}: ${message ?? 'failed'.tr}', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text('retry'.tr),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    MultiSearchLogic logic, {
    required List<Gallery> items,
    Widget? footer,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int crossAxisCount = (constraints.maxWidth / 190).floor().clamp(2, 7);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    final Gallery gallery = items[index];
                    final Set<GallerySource> alsoOn = logic.state.crossMatches[gallery.gid] ?? const <GallerySource>{};
                    return _MultiSearchCard(
                      gallery: gallery,
                      alsoOn: alsoOn,
                      isAlreadyRead: alreadyReadService.isAlreadyRead(gallery),
                      isLocalFavorite: localFavoriteService.contains(gallery.gid),
                      onTap: () => _openGallery(gallery),
                      onContextMenu: (Offset pos) => _showCardMenu(context, gallery, position: pos),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
            if (footer != null) SliverToBoxAdapter(child: footer),
          ],
        );
      },
    );
  }

  void _openGallery(Gallery gallery) {
    switch (gallery.galleryUrl.source) {
      case GallerySource.eh:
        toRoute(
          Routes.details,
          arguments: DetailsPageArgument(galleryUrl: gallery.galleryUrl, gallery: gallery),
        );
        break;
      case GallerySource.xlecx:
        toRoute(Routes.xlecxDetails, arguments: gallery);
        break;
      case GallerySource.nhentai:
        toRoute(Routes.nhentaiDetails, arguments: gallery);
        break;
    }
  }

  void _showCardMenu(BuildContext context, Gallery gallery, {Offset? position}) {
    final bool isRead = alreadyReadService.isAlreadyRead(gallery);
    final bool isFav = localFavoriteService.contains(gallery.gid);

    showEHContextMenu(
      context,
      position: position,
      actions: [
        EHContextMenuAction(
          text: isRead ? 'removeFromAlreadyRead'.tr : 'markAsAlreadyRead'.tr,
          icon: Icon(isRead ? Icons.check_circle : Icons.check_circle_outline, size: 18),
          onTap: () async {
            final bool added = await alreadyReadService.toggle(gallery2GalleryHistoryModel(gallery));
            toast(added ? 'alreadyReadAdded'.tr : 'alreadyReadRemoved'.tr);
          },
        ),
        EHContextMenuAction(
          text: isFav ? 'removeFromLocalFavorites'.tr : 'addToLocalFavorites'.tr,
          icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, size: 18),
          onTap: () async {
            final bool added = await localFavoriteService.toggle(gallery);
            toast(added ? 'localFavoriteAdded'.tr : 'localFavoriteRemoved'.tr);
          },
        ),
      ],
    );
  }

  static String _sourceLabel(GallerySource source) {
    switch (source) {
      case GallerySource.eh:
        return 'E-Hentai';
      case GallerySource.xlecx:
        return 'Xlecx';
      case GallerySource.nhentai:
        return 'nhentai';
    }
  }
}

class _MultiSearchCard extends StatelessWidget {
  final Gallery gallery;
  final Set<GallerySource> alsoOn;
  final bool isAlreadyRead;
  final bool isLocalFavorite;
  final VoidCallback onTap;
  final void Function(Offset position) onContextMenu;

  const _MultiSearchCard({
    required this.gallery,
    required this.alsoOn,
    required this.isAlreadyRead,
    required this.isLocalFavorite,
    required this.onTap,
    required this.onContextMenu,
  });

  Color _sourceBadgeColor(GallerySource source) {
    switch (source) {
      case GallerySource.eh:
        return const Color(0xFF5C4B99);
      case GallerySource.xlecx:
        return const Color(0xFFD96B27);
      case GallerySource.nhentai:
        return const Color(0xFFED2553);
    }
  }

  @override
  Widget build(BuildContext context) {
    final GallerySource source = gallery.galleryUrl.source;

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        onSecondaryTapDown: (TapDownDetails d) => onContextMenu(d.globalPosition),
        onLongPress: () {
          final RenderBox? box = context.findRenderObject() as RenderBox?;
          final Offset pos = box == null ? Offset.zero : box.localToGlobal(box.size.center(Offset.zero));
          onContextMenu(pos);
        },
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: EHImage(
                      galleryImage: gallery.cover,
                      autoLayout: true,
                      fit: BoxFit.cover,
                      containerColor: UIConfig.galleryCardBackGroundColor(context),
                      borderRadius: BorderRadius.circular(10),
                      maxBytes: 384 * 1024,
                      loadingWidgetBuilder: () => const SizedBox.shrink(),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _sourceBadgeColor(source).withValues(alpha: 0.90),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          MultiSearchPage._sourceLabel(source),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  if (isLocalFavorite || isAlreadyRead)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isAlreadyRead)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.check_circle, size: 14, color: Colors.lightGreenAccent),
                              ),
                            ),
                          if (isLocalFavorite) ...[
                            if (isAlreadyRead) const SizedBox(width: 4),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.favorite, size: 14, color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (alsoOn.isNotEmpty)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            '+ ${alsoOn.map(MultiSearchPage._sourceLabel).join(', ')}',
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  if (gallery.pageCount != null && gallery.pageCount! > 0)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          child: Text(
                            '${gallery.pageCount}P',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              gallery.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}
