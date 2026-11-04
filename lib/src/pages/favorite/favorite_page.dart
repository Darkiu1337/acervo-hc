import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
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
        if (state.galleries.isNotEmpty)
          IconButton(
            tooltip: 'deleteAll'.tr,
            icon: const Icon(Icons.delete_outline_outlined, size: 27),
            onPressed: logic.handleTapDeleteLocalFavorites,
          ),
      ];
    }

    return [
      if (state.galleries.isNotEmpty) IconButton(icon: Icon(Icons.send, size: 20), onPressed: logic.handleTapJumpButton),
      if (state.galleries.isNotEmpty) IconButton(icon: const Icon(Icons.sort), onPressed: logic.handleChangeSortOrder),
      IconButton(icon: const Icon(Icons.filter_alt_outlined, size: 28), onPressed: logic.handleTapFilterButton),
    ];
  }

  @override
  Widget buildBody(BuildContext context) {
    return Column(
      children: [
        _buildModeSwitcher(context),
        Expanded(
          child: state.localMode && state.galleries.isEmpty && state.loadingState == LoadingState.noData
              ? _buildLocalEmptyState(context)
              : super.buildBody(context),
        ),
      ],
    );
  }

  /// Switches between the online E-H favorites and the local (Xlecx) list.
  Widget _buildModeSwitcher(BuildContext context) {
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
          if (state.localMode && state.galleries.isNotEmpty)
            Text(
              '${state.galleries.length}',
              style: TextStyle(color: UIConfig.galleryCardTextColor(context)),
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
}
