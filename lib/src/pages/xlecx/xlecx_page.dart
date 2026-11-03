import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/pages/xlecx/xlecx_logic.dart';
import 'package:acervo_hc/src/routes/routes.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/utils/convert_util.dart';
import 'package:acervo_hc/src/utils/route_util.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/eh_context_menu.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';
import 'package:acervo_hc/src/widget/xlecx_card.dart';
import 'package:acervo_hc/src/widget/xlecx_filter_sheet.dart';
import 'package:acervo_hc/src/widget/xlecx_mark.dart';
import 'package:acervo_hc/src/widget/xlecx_search_bar.dart';

/// Browse/search page of the external Xlecx source.
class XlecxPage extends StatelessWidget {
  const XlecxPage({Key? key}) : super(key: key);

  XlecxLogic get logic {
    if (Get.isRegistered<XlecxLogic>()) {
      return Get.find<XlecxLogic>();
    }
    return Get.put<XlecxLogic>(XlecxLogic(), permanent: true);
  }

  @override
  Widget build(BuildContext context) {
    final XlecxLogic logic = this.logic;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const XlecxMark(size: 22),
            const SizedBox(width: 10),
            Text('xlecx'.tr),
          ],
        ),
      ),
      body: Column(
        children: [
          XlecxSearchBar(
            logic: logic,
            onOpenFilters: () => _openFilters(context, logic),
          ),
          Expanded(
            child: GetBuilder<XlecxLogic>(
              id: logic.bodyId,
              builder: (_) => logic.state.showSuggestions ? _buildSuggestions(context, logic) : _buildResults(context, logic),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFilters(BuildContext context, XlecxLogic logic) async {
    final XlecxSearchConfig? config = await showXlecxFilterSheet(
      context: context,
      config: logic.state.config,
    );

    if (config != null) {
      await logic.applyConfig(config);
    }
  }

  Widget _buildSuggestions(BuildContext context, XlecxLogic logic) {
    final List<String> recent = logic.recentSearches;
    final List<XlecxTag> popular = logic.popularTags;

    /// Keeps taps inside the panel from counting as "outside the search field",
    /// which would unfocus it and remove the panel before the chip's onPressed
    /// runs.
    return TextFieldTapRegion(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: Text('search'.tr, style: Theme.of(context).textTheme.titleSmall)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: logic.hideSuggestions,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (recent.isNotEmpty) ...[
            Row(
              children: [
                Expanded(child: _sectionTitle(context, 'recentSearches'.tr)),
                TextButton(
                  onPressed: logic.clearRecentSearches,
                  child: Text('deleteAll'.tr),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final String keyword in recent)
                  InputChip(
                    label: Text(keyword),
                    onPressed: () => logic.submitKeyword(keyword),
                    onDeleted: () => logic.removeRecentSearch(keyword),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    deleteButtonTooltipMessage: 'delete'.tr,
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          _sectionTitle(context, 'popularTags'.tr),
          if (logic.loadingTags && popular.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final XlecxTag tag in popular)
                  ActionChip(
                    label: Text(tag.label),
                    onPressed: () => logic.toggleIncludeTag(tag),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _buildResults(BuildContext context, XlecxLogic logic) {
    return RefreshIndicator(
      onRefresh: logic.onRefresh,
      child: CustomScrollView(
        controller: logic.state.scrollController,
        slivers: [
          if (logic.state.galleries.isEmpty && logic.state.loadingState == LoadingState.loading)
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
                  if (index == logic.state.galleries.length - 1 && logic.state.loadingState == LoadingState.idle) {
                    SchedulerBinding.instance.addPostFrameCallback((_) => logic.loadMore());
                  }

                  final Gallery gallery = logic.state.galleries[index];
                  return Obx(() {
                    final bool isFavorite = localFavoriteService.contains(gallery.gid);
                    return XlecxCard(
                      gallery: gallery,
                      isFavorite: isFavorite,
                      onTap: () => toRoute(Routes.xlecxDetails, arguments: gallery),
                      onLongPress: () => _showCardMenu(context, gallery),
                      onSecondaryTap: (Offset position) => _showCardMenu(context, gallery, position: position),
                    );
                  });
                },
                childCount: logic.state.galleries.length,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildFooter(context, logic)),
        ],
      ),
    );
  }

  /// Long-press/right-click menu of a grid card: toggles the local favorite
  /// without opening the detail page.
  void _showCardMenu(BuildContext context, Gallery gallery, {Offset? position}) {
    final bool isFavorite = localFavoriteService.contains(gallery.gid);
    final bool isAlreadyRead = alreadyReadService.contains(gallery.gid);

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

  Widget _buildFooter(BuildContext context, XlecxLogic logic) {
    final LoadingState state = logic.state.loadingState;

    if (state == LoadingState.loading && logic.state.galleries.isNotEmpty) {
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
