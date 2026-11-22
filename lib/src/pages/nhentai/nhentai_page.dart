import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/nhentai_gallery.dart';
import 'package:acervo_hc/src/pages/nhentai/nhentai_logic.dart';
import 'package:acervo_hc/src/pages/nhentai/nhentai_state.dart';
import 'package:acervo_hc/src/routes/routes.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/utils/convert_util.dart';
import 'package:acervo_hc/src/utils/route_util.dart';
import 'package:acervo_hc/src/utils/search_util.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/eh_context_menu.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';
import 'package:acervo_hc/src/widget/nhentai_card.dart';
import 'package:acervo_hc/src/widget/nhentai_mark.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// Dedicated browse/search page for nhentai, styled consistently with [XlecxPage].
class NHentaiPage extends StatelessWidget {
  const NHentaiPage({Key? key}) : super(key: key);

  NHentaiLogic get logic {
    if (Get.isRegistered<NHentaiLogic>()) {
      return Get.find<NHentaiLogic>();
    }
    return Get.put<NHentaiLogic>(NHentaiLogic(), permanent: true);
  }

  @override
  Widget build(BuildContext context) {
    final NHentaiLogic logic = this.logic;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const NHentaiMark(size: 22),
            const SizedBox(width: 10),
            Text('nhentai'.tr),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'refresh'.tr,
            icon: const Icon(Icons.refresh),
            onPressed: logic.refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndFilters(context, logic),
          Expanded(
            child: GetBuilder<NHentaiLogic>(
              id: logic.bodyId,
              builder: (_) => _buildResults(context, logic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(BuildContext context, NHentaiLogic logic) {
    return GetBuilder<NHentaiLogic>(
      id: logic.filterBarId,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: logic.state.searchController,
                focusNode: logic.state.searchFocusNode,
                textInputAction: TextInputAction.search,
                onSubmitted: logic.submitSearch,
                decoration: InputDecoration(
                  hintText: 'nhentaiSearchHint'.tr,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: logic.state.query.isNotEmpty || logic.state.searchController.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'clear'.tr,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: logic.clearSearch,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final NHentaiSort sort in NHentaiSort.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(sort.labelKey.tr),
                          selected: logic.state.sort == sort,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => logic.setSort(sort),
                        ),
                      ),
                    const SizedBox(width: 8),
                    for (final NHentaiLanguage lang in NHentaiLanguage.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(lang.labelKey.tr),
                          selected: logic.state.language == lang,
                          visualDensity: VisualDensity.compact,
                          showCheckmark: false,
                          onSelected: (_) => logic.setLanguage(lang),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults(BuildContext context, NHentaiLogic logic) {
    return RefreshIndicator(
      onRefresh: logic.onRefresh,
      child: CustomScrollView(
        controller: logic.state.scrollController,
        slivers: [
          if (logic.state.items.isEmpty && logic.state.loadingState == LoadingState.loading)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisSpacing: 12,
                crossAxisSpacing: 8,
                childAspectRatio: 0.58,
              ),
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  if (index == logic.state.items.length - 1 && logic.state.loadingState == LoadingState.idle) {
                    SchedulerBinding.instance.addPostFrameCallback((_) => logic.loadMore());
                  }

                  final NHentaiCardItem item = logic.state.items[index];
                  final Gallery gallery = item.gallery;
                  return Obx(() {
                    final bool isFavorite = localFavoriteService.contains(gallery.gid);
                    return NHentaiCard(
                      gallery: gallery,
                      numFavorites: item.numFavorites,
                      isFavorite: isFavorite,
                      onTap: () => toRoute(Routes.nhentaiDetails, arguments: gallery),
                      onLongPress: () => _showCardMenu(context, gallery),
                      onSecondaryTap: (Offset position) => _showCardMenu(context, gallery, position: position),
                    );
                  });
                },
                childCount: logic.state.items.length,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildFooter(context, logic)),
        ],
      ),
    );
  }

  void _showCardMenu(BuildContext context, Gallery gallery, {Offset? position}) {
    final bool isFavorite = localFavoriteService.contains(gallery.gid);
    final bool isAlreadyRead = alreadyReadService.isAlreadyRead(gallery);

    showEHContextMenu(
      context,
      position: position,
      actions: [
        EHContextMenuAction(
          text: isFavorite ? 'removeFromLocalFavorites'.tr : 'addToLocalFavorites'.tr,
          icon: Icon(isFavorite ? Icons.favorite_border : Icons.favorite, size: 18),
          onTap: () => _toggleLocalFavorite(gallery),
        ),
        EHContextMenuAction(
          text: isAlreadyRead ? 'removeFromAlreadyRead'.tr : 'markAsAlreadyRead'.tr,
          icon: Icon(isAlreadyRead ? Icons.check_circle : Icons.check_circle_outline, size: 18),
          onTap: () => _toggleAlreadyRead(gallery),
        ),
        EHContextMenuAction(
          text: 'searchOnEHentai'.tr,
          icon: const Icon(Icons.search, size: 18),
          onTap: () => _searchOnEHentai(gallery.title),
        ),
        EHContextMenuAction(
          text: 'openInBrowser'.tr,
          icon: const Icon(Icons.open_in_browser, size: 18),
          onTap: () => launchUrlString(gallery.galleryUrl.url, mode: LaunchMode.externalApplication),
        ),
      ],
    );
  }

  Future<void> _toggleLocalFavorite(Gallery gallery) async {
    final bool added = await localFavoriteService.toggle(gallery);
    toast(added ? 'localFavoriteAdded'.tr : 'localFavoriteRemoved'.tr);
  }

  Future<void> _toggleAlreadyRead(Gallery gallery) async {
    final bool added = await alreadyReadService.toggle(gallery2GalleryHistoryModel(gallery));
    toast(added ? 'alreadyReadAdded'.tr : 'alreadyReadRemoved'.tr);
  }

  void _searchOnEHentai(String title) {
    final String cleaned = title.replaceAll(RegExp(r'\[.*?\]|\(.*?\)|\{.*?\}'), '').trim();
    if (cleaned.isEmpty) {
      return;
    }
    newSearch(keyword: '"$cleaned"', forceNewRoute: true);
  }

  Widget _buildFooter(BuildContext context, NHentaiLogic logic) {
    final LoadingState state = logic.state.loadingState;

    if (state == LoadingState.loading && logic.state.items.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state == LoadingState.error) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: TextButton.icon(
            onPressed: logic.loadMore,
            icon: const Icon(Icons.refresh),
            label: Text('retry'.tr),
          ),
        ),
      );
    }

    if (state == LoadingState.noData) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text('noData'.tr)),
      );
    }

    if (state == LoadingState.noMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text('noMore'.tr)),
      );
    }

    return const SizedBox(height: 20);
  }
}
