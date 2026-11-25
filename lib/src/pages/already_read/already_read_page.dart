import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

import '../base/base_page.dart';
import 'already_read_page_logic.dart';
import 'already_read_page_state.dart';

class AlreadyReadPage extends BasePage {
  AlreadyReadPage({
    Key? key,
    bool showMenuButton = false,
    bool showTitle = false,
    String? name,
  }) : super(
          key: key,
          showMenuButton: showMenuButton,
          showTitle: showTitle,
          showScroll2TopButton: true,
          name: name,
        );

  @override
  AlreadyReadPageLogic get logic => Get.put<AlreadyReadPageLogic>(AlreadyReadPageLogic(), permanent: true);

  @override
  AlreadyReadPageState get state => Get.find<AlreadyReadPageLogic>().state;

  @override
  List<Widget> buildAppBarActions() {
    return [
      if (state.totalStoredCount > 0) ...[
        PopupMenuButton<GallerySortOption>(
          tooltip: 'sortOrder'.tr,
          icon: const Icon(Icons.sort),
          initialValue: state.clientFilter.sortOrder,
          onSelected: logic.setSortOrder,
          itemBuilder: (_) => GallerySortOption.values
              .map(
                (GallerySortOption opt) => PopupMenuItem<GallerySortOption>(
                  value: opt,
                  child: Row(
                    children: [
                      if (state.clientFilter.sortOrder == opt)
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
            state.clientFilter.isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
            size: 26,
            color: state.clientFilter.isActive ? Get.theme.colorScheme.primary : null,
          ),
          onPressed: logic.handleTapClientFilterButton,
        ),
        IconButton(
          tooltip: 'deleteAll'.tr,
          icon: const Icon(Icons.delete_outline_outlined, size: 26),
          onPressed: logic.handleTapDeleteButton,
        ),
      ],
      ...super.buildAppBarActions(),
    ];
  }

  @override
  Widget buildBody(BuildContext context) {
    if (state.totalStoredCount == 0 && state.galleries.isEmpty && state.loadingState == LoadingState.noData) {
      return _buildEmptyState(context);
    }

    return Column(
      children: [
        if (state.totalStoredCount > 0) _buildFilterHeader(context),
        Expanded(
          child: state.galleries.isEmpty && state.loadingState == LoadingState.noData && state.clientFilter.hasFilter
              ? _buildFilteredEmptyState(context)
              : super.buildBody(context),
        ),
      ],
    );
  }

  Widget _buildFilterHeader(BuildContext context) {
    final Set<GallerySource> activeSources = state.clientFilter.sources;
    final Color hintColor = UIConfig.galleryCardTextColor(context);
    final String countText = state.clientFilter.hasFilter
        ? '${state.filteredTotalCount} / ${state.totalStoredCount}'
        : '${state.totalStoredCount}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: state.searchController,
                  textInputAction: TextInputAction.search,
                  onChanged: logic.onSearchKeywordChanged,
                  decoration: InputDecoration(
                    hintText: 'searchAlreadyReadHint'.tr,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: state.searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'clear'.tr,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: logic.clearSearchKeyword,
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(countText, style: TextStyle(color: hintColor, fontSize: 13)),
            ],
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
                  onSelected: (_) => logic.selectSingleSource(null),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('E-Hentai'),
                  selected: activeSources.length == 1 && activeSources.contains(GallerySource.eh),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => logic.selectSingleSource(GallerySource.eh),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Xlecx'),
                  selected: activeSources.length == 1 && activeSources.contains(GallerySource.xlecx),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => logic.selectSingleSource(GallerySource.xlecx),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('nhentai'),
                  selected: activeSources.length == 1 && activeSources.contains(GallerySource.nhentai),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => logic.selectSingleSource(GallerySource.nhentai),
                ),
                if (state.clientFilter.isActive) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.clear, size: 16),
                    label: Text('reset'.tr),
                    visualDensity: VisualDensity.compact,
                    onPressed: logic.clearAllFilters,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final Color hintColor = UIConfig.galleryCardTextColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: hintColor),
            const SizedBox(height: 12),
            Text('noAlreadyRead'.tr, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('noAlreadyReadHint'.tr, textAlign: TextAlign.center, style: TextStyle(color: hintColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredEmptyState(BuildContext context) {
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
              onPressed: logic.clearAllFilters,
            ),
          ],
        ),
      ),
    );
  }
}
