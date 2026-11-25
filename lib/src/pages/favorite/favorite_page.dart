import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

import '../base/base_page.dart';
import 'favorite_page_logic.dart';
import 'favorite_page_state.dart';

class FavoritePage extends BasePage {
  const FavoritePage({
    Key? key,
    bool showMenuButton = false,
    bool showTitle = false,
    String? name,
  }) : super(
          key: key,
          showMenuButton: showMenuButton,
          showJumpButton: true,
          showFilterButton: true,
          showScroll2TopButton: true,
          showTitle: showTitle,
          name: name,
        );

  @override
  FavoritePageLogic get logic => Get.put<FavoritePageLogic>(FavoritePageLogic(), permanent: true);

  @override
  FavoritePageState get state => Get.find<FavoritePageLogic>().state;

  @override
  List<Widget> buildAppBarActions() {
    if (state.localMode) {
      return [
        if (state.totalLocalCount > 0) ...[
          PopupMenuButton<GallerySortOption>(
            tooltip: 'sortOrder'.tr,
            icon: const Icon(Icons.sort),
            initialValue: state.localFilter.sortOrder,
            onSelected: logic.setLocalSortOrder,
            itemBuilder: (_) => GallerySortOption.values
                .map(
                  (GallerySortOption opt) => PopupMenuItem<GallerySortOption>(
                    value: opt,
                    child: Row(
                      children: [
                        if (state.localFilter.sortOrder == opt)
                          const Icon(Icons.check, size: 16)
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Text(opt.labelKey.tr),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          IconButton(
            tooltip: 'clientFilter'.tr,
            icon: Icon(
              state.localFilter.isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
              size: 26,
              color: state.localFilter.isActive ? Get.theme.colorScheme.primary : null,
            ),
            onPressed: logic.handleTapLocalFilterButton,
          ),
          IconButton(
            tooltip: 'deleteAll'.tr,
            icon: const Icon(Icons.delete_outline_outlined, size: 26),
            onPressed: logic.handleTapDeleteLocalFavorites,
          ),
        ],
      ];
    }

    return [
      if (state.galleries.isNotEmpty) IconButton(icon: const Icon(Icons.send, size: 20), onPressed: logic.handleTapJumpButton),
      if (state.galleries.isNotEmpty) IconButton(icon: const Icon(Icons.sort), onPressed: logic.handleChangeSortOrder),
      IconButton(icon: const Icon(Icons.filter_alt_outlined, size: 28), onPressed: logic.handleTapFilterButton),
    ];
  }

  @override
  Widget buildBody(BuildContext context) {
    final bool hasLocalFilters = state.localFilter.hasFilter || state.selectedCollection != null;

    return Column(
      children: [
        _buildModeSwitcher(context),
        if (state.localMode && state.totalLocalCount > 0) _buildLocalFiltersAndCollections(context),
        Expanded(
          child: state.localMode && state.galleries.isEmpty && state.loadingState == LoadingState.noData
              ? (hasLocalFilters ? _buildLocalFilteredEmptyState(context) : _buildLocalEmptyState(context))
              : super.buildBody(context),
        ),
      ],
    );
  }

  /// Switches between the online E-H favorites and the local list.
  Widget _buildModeSwitcher(BuildContext context) {
    final bool hasLocalFilters = state.localFilter.hasFilter || state.selectedCollection != null;
    final String countText = hasLocalFilters
        ? '${state.galleries.length} / ${state.totalLocalCount}'
        : '${state.totalLocalCount}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  selected: !state.localMode,
                  avatar: const Icon(Icons.cloud_outlined, size: 16),
                  label: const Text('E-Hentai'),
                  onSelected: (_) => logic.switchMode(false),
                ),
                ChoiceChip(
                  selected: state.localMode,
                  avatar: const Icon(Icons.favorite, size: 16),
                  label: Text('localFavorites'.tr),
                  onSelected: (_) => logic.switchMode(true),
                ),
              ],
            ),
          ),
          if (state.localMode && state.totalLocalCount > 0)
            Text(
              countText,
              style: TextStyle(color: UIConfig.galleryCardTextColor(context)),
            ),
        ],
      ),
    );
  }

  Widget _buildLocalFiltersAndCollections(BuildContext context) {
    final Set<GallerySource> activeSources = state.localFilter.sources;
    final List<String> collections = localFavoriteService.collections;
    final bool hasAnyFilter = state.localFilter.isActive || state.selectedCollection != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: state.localSearchController,
            textInputAction: TextInputAction.search,
            onChanged: logic.onLocalSearchChanged,
            decoration: InputDecoration(
              hintText: 'searchLocalFavoritesHint'.tr,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: state.localSearchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'clear'.tr,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: logic.clearLocalSearch,
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('all'.tr),
                  selected: activeSources.isEmpty,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => logic.selectLocalSource(null),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Xlecx'),
                  selected: activeSources.length == 1 && activeSources.contains(GallerySource.xlecx),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => logic.selectLocalSource(GallerySource.xlecx),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('nhentai'),
                  selected: activeSources.length == 1 && activeSources.contains(GallerySource.nhentai),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => logic.selectLocalSource(GallerySource.nhentai),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('E-Hentai'),
                  selected: activeSources.length == 1 && activeSources.contains(GallerySource.eh),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => logic.selectLocalSource(GallerySource.eh),
                ),
                if (hasAnyFilter) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.clear, size: 16),
                    label: Text('reset'.tr),
                    visualDensity: VisualDensity.compact,
                    onPressed: logic.clearLocalFilters,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.folder_outlined, size: 15),
                  label: Text('allCollections'.tr),
                  selected: state.selectedCollection == null,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => logic.selectLocalCollection(null),
                ),
                const SizedBox(width: 6),
                ...collections.map((String col) {
                  final int count = localFavoriteService.countInCollection(col);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onSecondaryTapDown: (TapDownDetails d) =>
                          logic.handleManageCollectionMenu(context, col, position: d.globalPosition),
                      onLongPressStart: (LongPressStartDetails d) =>
                          logic.handleManageCollectionMenu(context, col, position: d.globalPosition),
                      child: ChoiceChip(
                        label: Text('$col ($count)'),
                        selected: state.selectedCollection == col,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => logic.selectLocalCollection(col),
                      ),
                    ),
                  );
                }),
                ActionChip(
                  avatar: const Icon(Icons.create_new_folder_outlined, size: 16),
                  label: Text('newCollection'.tr),
                  visualDensity: VisualDensity.compact,
                  onPressed: logic.handleCreateCollection,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalEmptyState(BuildContext context) {
    final Color hintColor = UIConfig.galleryCardTextColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 56, color: hintColor),
            const SizedBox(height: 12),
            Text('noLocalFavorites'.tr, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('noLocalFavoritesHint'.tr, textAlign: TextAlign.center, style: TextStyle(color: hintColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalFilteredEmptyState(BuildContext context) {
    final Color hintColor = UIConfig.galleryCardTextColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_off_outlined, size: 48, color: hintColor),
            const SizedBox(height: 12),
            Text('noData'.tr, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.clear),
              label: Text('reset'.tr),
              onPressed: logic.clearLocalFilters,
            ),
          ],
        ),
      ),
    );
  }
}
