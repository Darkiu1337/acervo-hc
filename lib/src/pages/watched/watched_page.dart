import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/pages/watched/watched_page_state.dart';
import 'package:acervo_hc/src/service/watched_progress_service.dart';
import 'package:acervo_hc/src/setting/style_setting.dart';
import 'package:acervo_hc/src/widget/eh_gallery_collection.dart';

import '../base/base_page.dart';
import 'watched_page_logic.dart';

class WatchedPage extends BasePage {
  const WatchedPage({
    Key? key,
    bool showMenuButton = false,
    bool showTitle = false,
    String? name,
  }) : super(
          key: key,
          showMenuButton: showMenuButton,
          showJumpButton: true,
          showFilterButton: true,
          showTitle: showTitle,
          showScroll2TopButton: true,
          name: name,
        );

  @override
  WatchedPageLogic get logic => Get.put<WatchedPageLogic>(WatchedPageLogic(), permanent: true);

  @override
  WatchedPageState get state => Get.find<WatchedPageLogic>().state;

  @override
  List<Widget> buildAppBarActions() {
    return [
      IconButton(
        tooltip: 'watchedProgress'.tr,
        icon: const Icon(Icons.history_toggle_off, size: 22),
        onPressed: logic.openWatchedProgressPage,
      ),
      ...super.buildAppBarActions(),
    ];
  }

  @override
  Widget buildGalleryCollection(BuildContext context) {
    return Obx(() {
      watchedProgressService.revision.value;
      return EHGalleryCollection(
        key: state.galleryCollectionKey,
        context: context,
        galleries: state.galleries,
        listMode: styleSetting.pageListMode[state.route] ?? styleSetting.listMode.value,
        loadingState: state.loadingState,
        handleTapCard: logic.handleTapGalleryCard,
        handleLongPressCard: (gallery, position) => logic.handleLongPressCard(context, gallery, position: position),
        handleSecondaryTapCard: (gallery, position) => logic.handleSecondaryTapCard(context, gallery, position: position),
        handleLoadMore: logic.loadMore,
        isDimmed: (gallery) => watchedProgressService.isSeen(gallery.gid),
      );
    });
  }
}
