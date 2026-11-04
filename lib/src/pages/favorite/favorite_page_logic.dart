import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/extension/dio_exception_extension.dart';
import 'package:acervo_hc/src/extension/get_logic_extension.dart';
import 'package:acervo_hc/src/model/gallery_page.dart';
import 'package:acervo_hc/src/network/eh_request.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/setting/user_setting.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/eh_alert_dialog.dart';
import 'package:acervo_hc/src/widget/eh_context_menu.dart';
import 'package:acervo_hc/src/widget/eh_favorite_sort_order_dialog.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

import '../../enum/config_enum.dart';
import '../../exception/eh_site_exception.dart';
import '../../model/gallery.dart';
import '../../model/search_config.dart';
import '../../service/local_config_service.dart';
import '../../utils/eh_spider_parser.dart';
import '../../service/log.dart';
import '../../utils/snack_util.dart';
import '../../utils/uuid_util.dart';
import '../base/base_page_logic.dart';
import 'favorite_page_state.dart';

class FavoritePageLogic extends BasePageLogic {
  @override
  final FavoritePageState state = FavoritePageState();

  Worker? _favoritesWorker;

  /// Bumped on every mode switch so an online response that arrives after the
  /// user moved to the local list is discarded instead of polluting it.
  int _modeEpoch = 0;

  @override
  bool get useSearchConfig => true;

  @override
  bool get autoLoadNeedLogin => true;

  /// Local mode never touches the network, so it must not auto-load the E-H
  /// favorites (that path would also block on login).
  @override
  bool get autoLoadForFirstTime => !state.localMode;

  /// Favorites are a deliberate list: never hide an already-read gallery here.
  @override
  bool get hideAlreadyReadGalleries => false;

  @override
  Future<void> onInit() async {
    state.localMode = !userSetting.hasLoggedIn();

    localFavoriteService.ensureRestored();

    await super.onInit();

    /// Keep the local list in sync when a gallery is favorited/unfavorited from
    /// another page (e.g. the Xlecx details page on desktop).
    _favoritesWorker = ever(localFavoriteService.favorites, (_) {
      if (state.localMode) {
        _loadLocalFavorites(scrollToTop: false);
      }
    });

    if (state.localMode) {
      _loadLocalFavorites(scrollToTop: false);
    }
  }

  @override
  void onClose() {
    _favoritesWorker?.dispose();
    super.onClose();
  }

  Future<void> switchMode(bool localMode) async {
    if (state.localMode == localMode) {
      return;
    }

    if (!localMode && !userSetting.hasLoggedIn()) {
      toast('needLoginToOperate'.tr);
      return;
    }

    state.localMode = localMode;
    _modeEpoch++;

    state.galleries.clear();
    state.galleryCollectionKey = Key(newUUID());
    state.prevGid = null;
    state.nextGid = null;
    state.totalCount = null;

    jump2Top();
    updateSafely();

    if (localMode) {
      _loadLocalFavorites(scrollToTop: false);
    } else {
      loadMore(checkLoadingState: false);
    }
  }

  void _loadLocalFavorites({bool scrollToTop = true}) {
    final List<Gallery> favorites = List<Gallery>.of(localFavoriteService.favorites);

    state.galleries
      ..clear()
      ..addAll(favorites);

    state.totalCount = null;
    state.prevGid = null;
    state.nextGid = null;
    state.loadingState = favorites.isEmpty ? LoadingState.noData : LoadingState.noMore;
    state.galleryCollectionKey = Key(newUUID());

    if (scrollToTop) {
      jump2Top();
    }

    updateSafely();
  }

  @override
  Future<void> loadMore({bool checkLoadingState = true}) async {
    if (state.localMode) {
      return;
    }

    final int epoch = _modeEpoch;
    await super.loadMore(checkLoadingState: checkLoadingState);

    if (epoch != _modeEpoch) {
      _loadLocalFavorites(scrollToTop: false);
    }
  }

  @override
  Future<void> handleRefresh({String? updateId}) async {
    if (state.localMode) {
      _loadLocalFavorites();
      return;
    }

    final int epoch = _modeEpoch;
    await super.handleRefresh(updateId: updateId);

    if (epoch != _modeEpoch) {
      _loadLocalFavorites(scrollToTop: false);
    }
  }

  @override
  Future<void> handlePullDown() async {
    if (state.localMode) {
      _loadLocalFavorites();
      return;
    }

    return super.handlePullDown();
  }

  @override
  Future<void> handleClearAndRefresh() async {
    if (state.localMode) {
      _loadLocalFavorites();
      return;
    }

    return super.handleClearAndRefresh();
  }

  @override
  Future<void> handleTapJumpButton() async {
    if (state.localMode) {
      return;
    }

    return super.handleTapJumpButton();
  }

  Future<void> handleTapDeleteLocalFavorites() async {
    bool? result = await Get.dialog(EHDialog(title: '${'deleteAll'.tr}?'));

    if (result == true) {
      await localFavoriteService.clear();
    }
  }

  @override
  void handleLongPressCard(BuildContext context, Gallery gallery, {Offset? position}) {
    if (!state.localMode) {
      return;
    }

    showEHContextMenu(
      context,
      position: position,
      actions: [
        EHContextMenuAction(
          text: 'removeFromLocalFavorites'.tr,
          icon: const Icon(Icons.favorite_border, size: 18),
          color: UIConfig.alertColor(context),
          onTap: () => localFavoriteService.remove(gallery.gid),
        ),
      ],
    );
  }

  @override
  void handleSecondaryTapCard(BuildContext context, Gallery gallery, {Offset? position}) {
    handleLongPressCard(context, gallery, position: position);
  }

  Future<void> handleChangeSortOrder() async {
    if (state.localMode) {
      return;
    }

    if (state.refreshState == LoadingState.loading) {
      return;
    }

    FavoriteSortOrder? result = await Get.dialog(EHFavoriteSortOrderDialog(init: state.favoriteSortOrder));
    if (result == null) {
      return;
    }

    if (state.refreshState == LoadingState.loading) {
      return;
    }

    state.loadingState = LoadingState.loading;

    state.galleries.clear();
    state.prevGid = null;
    state.nextGid = null;
    state.seek = DateTime.now();
    state.totalCount = null;
    state.favoriteSortOrder = null;

    jump2Top();

    updateSafely();

    try {
      await ehRequest.requestChangeFavoriteSortOrder(result, parser: EHSpiderParser.galleryPage2GalleryPageInfo);
    } on DioException catch (e) {
      /// handle with domain fronting, manually load more
      if (e.response?.statusCode == 403 && e.response!.redirects.isNotEmpty) {
        return loadMore(checkLoadingState: false);
      }

      log.error('change favorite sort order fail', e.errorMsg);
      snack('failed'.tr, e.errorMsg ?? '');
      state.loadingState = LoadingState.error;
      updateSafely([loadingStateId]);
      return;
    } on EHSiteException catch (e) {
      log.error('change favorite sort order fail', e.message);
      snack('failed'.tr, e.message);
      state.loadingState = LoadingState.error;
      updateSafely([loadingStateId]);
      return;
    } catch (e) {
      log.error('change favorite sort order fail', e.toString);
      snack('failed'.tr, e.toString());
      state.loadingState = LoadingState.error;
      updateSafely([loadingStateId]);
      return;
    }

    return loadMore(checkLoadingState: false);
  }

  @override
  Future<void> saveSearchConfig(SearchConfig searchConfig) async {
    await localConfigService.write(
      configKey: ConfigEnum.searchConfig,
      subConfigKey: searchConfigKey,
      value: jsonEncode(searchConfig.copyWith(keyword: '', tags: [])),
    );
  }
}
