import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/extension/get_logic_extension.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_page.dart';
import 'package:acervo_hc/src/pages/watched/progress/watched_progress_page.dart';
import 'package:acervo_hc/src/pages/watched/watched_page_state.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/watched_progress_service.dart';
import 'package:acervo_hc/src/utils/convert_util.dart';
import 'package:acervo_hc/src/utils/snack_util.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/utils/uuid_util.dart';
import 'package:acervo_hc/src/widget/eh_context_menu.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

import '../../enum/config_enum.dart';
import '../../model/search_config.dart';
import '../../service/local_config_service.dart';
import '../base/base_page_logic.dart';

class WatchedPageLogic extends BasePageLogic {
  @override
  bool get useSearchConfig => true;

  @override
  bool get autoLoadNeedLogin => true;

  @override
  final WatchedPageState state = WatchedPageState();

  Timer? _scrollSeenTimer;

  @override
  Future<void> onInit() async {
    await watchedProgressService.ensureLoaded();
    await super.onInit();
  }

  @override
  void onClose() {
    _scrollSeenTimer?.cancel();
    super.onClose();
  }

  @override
  Future<void> saveSearchConfig(SearchConfig searchConfig) async {
    await localConfigService.write(
      configKey: ConfigEnum.searchConfig,
      subConfigKey: searchConfigKey,
      value: jsonEncode(searchConfig.copyWith(keyword: '', tags: [])),
    );
  }

  @override
  bool onUserScroll(UserScrollNotification notification) {
    final bool handled = super.onUserScroll(notification);
    _scrollSeenTimer?.cancel();
    _scrollSeenTimer = Timer(const Duration(milliseconds: 600), _markScrolledPastAsSeen);
    return handled;
  }

  void _markScrolledPastAsSeen() {
    if (state.galleries.isEmpty || !state.scrollController.hasClients) {
      return;
    }
    final double offset = state.scrollController.offset;
    final double maxExtent = state.scrollController.position.maxScrollExtent;
    if (offset <= 40 || maxExtent <= 0) {
      return;
    }
    final double fraction = (offset / (maxExtent + 400)).clamp(0.0, 1.0);
    final int passedCount = (fraction * state.galleries.length).floor().clamp(0, state.galleries.length);
    if (passedCount <= 0) {
      return;
    }
    final List<int> passedGids = state.galleries.take(passedCount).map((g) => g.gid).toList();
    unawaited(watchedProgressService.markSeen(passedGids));
  }

  @override
  void handleTapGalleryCard(Gallery gallery) {
    unawaited(watchedProgressService.setLastAnchor(gallery));
    super.handleTapGalleryCard(gallery);
  }

  @override
  void handleLongPressCard(BuildContext context, Gallery gallery, {Offset? position}) {
    final bool seen = watchedProgressService.isSeen(gallery.gid);
    final bool bookmarked = watchedProgressService.isBookmarked(gallery.gid);
    final bool alreadyRead = alreadyReadService.isAlreadyRead(gallery);

    showEHContextMenu(
      context,
      position: position,
      actions: [
        EHContextMenuAction(
          text: bookmarked ? 'watchedRemoveBookmark'.tr : 'watchedAddBookmark'.tr,
          onTap: () async {
            final bool added = await watchedProgressService.toggleBookmark(gallery);
            toast(added ? 'watchedBookmarkAdded'.tr : 'watchedBookmarkRemoved'.tr);
          },
        ),
        EHContextMenuAction(
          text: seen ? 'watchedMarkUnseen'.tr : 'watchedMarkSeen'.tr,
          onTap: () => watchedProgressService.toggleSeen(gallery.gid),
        ),
        EHContextMenuAction(
          text: alreadyRead ? 'removeFromAlreadyRead'.tr : 'markRead'.tr,
          onTap: () async {
            final bool added = await alreadyReadService.toggle(gallery2GalleryHistoryModel(gallery));
            toast(added ? 'alreadyReadAdded'.tr : 'alreadyReadRemoved'.tr);
          },
        ),
      ],
    );
  }

  @override
  void handleSecondaryTapCard(BuildContext context, Gallery gallery, {Offset? position}) {
    handleLongPressCard(context, gallery, position: position);
  }

  void openWatchedProgressPage() {
    Get.to(
      () => WatchedProgressPage(
        onJumpToGid: (int gid) => jumpToGid(gid),
      ),
    );
  }

  /// Jumps the Watched feed so it starts right at [gid].
  Future<void> jumpToGid(int gid) async {
    if (state.loadingState == LoadingState.loading) {
      return;
    }
    log.info('Watched: jump to gid $gid');
    state.galleries.clear();
    state.loadingState = LoadingState.loading;
    updateSafely();
    if (state.scrollController.hasClients) {
      state.scrollController.jumpTo(0);
    }

    try {
      final GalleryPageInfo galleryPage = await getGalleryPage(nextGid: (gid + 1).toString());
      final List<Gallery> galleries = await postHandleNewGalleries(galleryPage.galleries, cleanDuplicate: false);
      state.galleries = galleries;
      state.totalCount = galleryPage.totalCount;
      state.prevGid = galleryPage.prevGid;
      state.nextGid = galleryPage.nextGid;
      state.favoriteSortOrder = galleryPage.favoriteSortOrder;
      state.galleryCollectionKey = Key(newUUID());
      if (state.nextGid == null && state.prevGid == null && state.galleries.isEmpty) {
        state.loadingState = LoadingState.noData;
      } else if (state.nextGid == null) {
        state.loadingState = LoadingState.noMore;
      } else {
        state.loadingState = LoadingState.idle;
      }
      updateSafely();
    } catch (e) {
      log.error('Watched jump to gid $gid failed: $e');
      snack('getGalleriesFailed'.tr, e.toString(), isShort: true);
      state.loadingState = LoadingState.error;
      updateSafely([loadingStateId]);
    }
  }
}
