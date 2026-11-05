import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/enum/config_enum.dart';
import 'package:acervo_hc/src/extension/dio_exception_extension.dart';
import 'package:acervo_hc/src/extension/get_logic_extension.dart';
import 'package:acervo_hc/src/model/gallery_page.dart';
import 'package:acervo_hc/src/model/search_config.dart';
import 'package:acervo_hc/src/service/local_config_service.dart';
import 'package:acervo_hc/src/setting/preference_setting.dart';
import 'package:acervo_hc/src/widget/eh_search_config_dialog.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../exception/eh_site_exception.dart';
import '../../mixin/scroll_to_top_logic_mixin.dart';
import '../../mixin/scroll_to_top_state_mixin.dart';
import '../../model/gallery.dart';
import '../../model/gallery_source.dart';
import '../../model/gallery_tag.dart';
import '../../network/eh_request.dart';
import '../../routes/routes.dart';
import '../../service/already_read_service.dart';
import '../../service/local_block_rule_service.dart';
import '../../service/read_progress_service.dart';
import '../../service/tag_translation_service.dart';
import '../../setting/user_setting.dart';
import '../../utils/eh_spider_parser.dart';
import '../../service/log.dart';
import '../../utils/route_util.dart';
import '../../utils/snack_util.dart';
import '../../utils/toast_util.dart';
import '../../utils/uuid_util.dart';
import '../../widget/loading_state_indicator.dart';
import '../details/details_page_logic.dart';
import 'base_page_state.dart';

abstract class BasePageLogic extends GetxController with Scroll2TopLogicMixin {
  BasePageState get state;

  @override
  Scroll2TopStateMixin get scroll2TopState => state;

  final String appBarId = 'appBarId';
  final String bodyId = 'bodyId';
  final String refreshStateId = 'refreshStateId';
  final String loadingStateId = 'loadingStateId';

  bool get useSearchConfig;

  String get searchConfigKey => runtimeType.toString();

  bool get autoLoadForFirstTime => true;

  bool get autoLoadNeedLogin => false;

  /// Whether galleries marked as "already read" are removed from this page.
  ///
  /// Off on the pages whose purpose is to list them again (Favorites, History,
  /// Ranklist and the Already read page itself).
  bool get hideAlreadyReadGalleries => true;

  Worker? _alreadyReadWorker;

  @override
  Future<void> onInit() async {
    super.onInit();

    alreadyReadService.ensureRestored();

    /// A gallery marked as read from the details page disappears from the open
    /// listing without needing a refresh.
    _alreadyReadWorker = ever(alreadyReadService.galleries, (_) {
      if (!hideAlreadyReadGalleries || state.galleries.isEmpty) {
        return;
      }

      final int length = state.galleries.length;
      state.galleries.removeWhere((gallery) => alreadyReadService.contains(gallery.gid));

      if (state.galleries.length != length) {
        updateSafely();
      }
    });

    if (useSearchConfig) {
      localConfigService.read(configKey: ConfigEnum.searchConfig, subConfigKey: searchConfigKey).then((searchConfigString) {
        if (searchConfigString != null) {
          Map<String, dynamic> map = jsonDecode(searchConfigString);
          state.searchConfig = SearchConfig.fromJson(map);
        }
      }).whenComplete(() {
        state.searchConfigInitCompleter.complete();
      });
    } else {
      state.searchConfigInitCompleter.complete();
    }

    if (autoLoadForFirstTime) {
      if (autoLoadNeedLogin && !userSetting.hasLoggedIn()) {
        state.loadingState = LoadingState.noData;
        updateSafely([bodyId]);
        Get.engine.addPostFrameCallback((_) => toast('needLoginToOperate'.tr));
        return;
      }

      loadMore();
    }
  }

  @override
  void onClose() {
    _alreadyReadWorker?.dispose();
    super.onClose();
  }

  /// pull-down
  Future<void> handlePullDown() async {
    if (state.prevGid == null) {
      return handleRefresh();
    }

    return loadBefore();
  }

  /// not clear current data before refresh
  /// [updateId] is for subclass to override
  Future<void> handleRefresh({String? updateId}) async {
    if (state.refreshState == LoadingState.loading) {
      return;
    }

    state.refreshState = LoadingState.loading;
    updateSafely([refreshStateId]);

    GalleryPageInfo galleryPage;
    try {
      galleryPage = await _getGalleryPageSkippingHidden();
    } on DioException catch (e) {
      log.error('refreshGalleryFailed'.tr, e.errorMsg);
      snack('refreshGalleryFailed'.tr, e.errorMsg ?? '', isShort: true);
      state.refreshState = LoadingState.error;
      updateSafely([refreshStateId]);
      return;
    } on EHSiteException catch (e) {
      log.error('refreshGalleryFailed'.tr, e.message);
      snack(
        'refreshGalleryFailed'.tr,
        e.message,
        isShort: true,
        onPressed: e.referLink == null ? null : () => launchUrlString(e.referLink!, mode: LaunchMode.externalApplication),
      );
      state.refreshState = LoadingState.error;
      updateSafely([refreshStateId]);
      return;
    } catch (e) {
      log.error('refreshGalleryFailed'.tr, e.toString());
      snack('refreshGalleryFailed'.tr, e.toString(), isShort: true);
      state.refreshState = LoadingState.error;
      updateSafely([refreshStateId]);
      return;
    }

    List<Gallery> galleries = await postHandleNewGalleries(galleryPage.galleries, cleanDuplicate: false);

    state.galleries = galleries;
    state.totalCount = galleryPage.totalCount;
    state.prevGid = galleryPage.prevGid;
    state.nextGid = galleryPage.nextGid;
    state.favoriteSortOrder = galleryPage.favoriteSortOrder;
    state.galleryCollectionKey = Key(newUUID());

    state.refreshState = LoadingState.idle;

    if (state.nextGid == null && state.prevGid == null && state.galleries.isEmpty) {
      state.loadingState = LoadingState.noData;
    } else if (state.nextGid == null) {
      state.loadingState = LoadingState.noMore;
    } else {
      state.loadingState = LoadingState.idle;
    }

    if (updateId != null) {
      updateSafely([updateId]);
    } else {
      updateSafely();
    }
  }

  /// clear current data first, then refresh
  Future<void> handleClearAndRefresh() async {
    if (state.loadingState == LoadingState.loading) {
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

    return loadMore(checkLoadingState: false);
  }

  /// pull-down to load page before(after jumping to a certain page), after load, we must restore [state.downloadState]
  /// to [prevState] in case of [prevState] is [noMore]
  Future<void> loadBefore() async {
    if (state.loadingState == LoadingState.loading) {
      return;
    }

    LoadingState prevState = state.loadingState;
    state.loadingState = LoadingState.loading;

    GalleryPageInfo galleryPage;
    try {
      galleryPage = await _getGalleryPageSkippingHidden(prevGid: state.prevGid);
    } on DioException catch (e) {
      log.error('getGalleriesFailed'.tr, e.errorMsg);
      snack('getGalleriesFailed'.tr, e.errorMsg ?? '', isShort: true);
      state.loadingState = prevState;
      updateSafely([loadingStateId]);
      return;
    } on EHSiteException catch (e) {
      log.error('getGalleriesFailed'.tr, e.message);
      snack(
        'getGalleriesFailed'.tr,
        e.message,
        isShort: true,
        onPressed: e.referLink == null ? null : () => launchUrlString(e.referLink!, mode: LaunchMode.externalApplication),
      );
      state.loadingState = prevState;
      updateSafely([loadingStateId]);
      return;
    } catch (e) {
      log.error('getGalleriesFailed'.tr, e.toString());
      snack('getGalleriesFailed'.tr, e.toString(), isShort: true);
      state.loadingState = prevState;
      updateSafely([loadingStateId]);
      return;
    }

    List<Gallery> galleries = await postHandleNewGalleries(galleryPage.galleries);

    state.galleries.insertAll(0, galleries);
    state.totalCount = galleryPage.totalCount;
    state.prevGid = galleryPage.prevGid;
    state.favoriteSortOrder = galleryPage.favoriteSortOrder;

    state.loadingState = prevState;

    updateSafely();
  }

  /// has scrolled to bottom, so need to load more data.
  Future<void> loadMore({bool checkLoadingState = true}) async {
    if (checkLoadingState && state.loadingState == LoadingState.loading) {
      return;
    }

    state.loadingState = LoadingState.loading;
    updateSafely([loadingStateId]);

    GalleryPageInfo galleryPage;
    try {
      galleryPage = await _getGalleryPageSkippingHidden(nextGid: state.nextGid);
    } on DioException catch (e) {
      log.error('getGalleriesFailed'.tr, e.errorMsg);
      snack('getGalleriesFailed'.tr, e.errorMsg ?? '', isShort: true);
      state.loadingState = LoadingState.error;
      updateSafely([loadingStateId]);
      return;
    } on EHSiteException catch (e) {
      log.error('getGalleriesFailed'.tr, e.message);
      snack(
        'getGalleriesFailed'.tr,
        e.message,
        isShort: true,
        onPressed: e.referLink == null ? null : () => launchUrlString(e.referLink!, mode: LaunchMode.externalApplication),
      );
      state.loadingState = LoadingState.error;
      updateSafely([loadingStateId]);
      return;
    } catch (e) {
      log.error('getGalleriesFailed'.tr, e.toString());
      snack('getGalleriesFailed'.tr, e.toString(), isShort: true);
      state.loadingState = LoadingState.error;
      updateSafely([loadingStateId]);
      return;
    }

    List<Gallery> galleries = await postHandleNewGalleries(galleryPage.galleries);

    state.galleries.addAll(galleries);
    state.totalCount = galleryPage.totalCount;
    state.nextGid = galleryPage.nextGid;
    state.favoriteSortOrder = galleryPage.favoriteSortOrder;

    if (state.nextGid == null && state.prevGid == null && state.galleries.isEmpty) {
      state.loadingState = LoadingState.noData;
    } else if (state.nextGid == null) {
      state.loadingState = LoadingState.noMore;
    } else {
      state.loadingState = LoadingState.idle;
    }

    updateSafely();
  }

  Future<void> jumpPage(DateTime dateTime) async {
    if (state.loadingState == LoadingState.loading) {
      return;
    }

    log.info('Jump page to $dateTime');

    state.galleries.clear();
    state.loadingState = LoadingState.loading;
    updateSafely();

    state.scrollController.jumpTo(0);

    GalleryPageInfo galleryPage;
    try {
      galleryPage = await getGalleryPage(nextGid: state.nextGid, prevGid: state.prevGid, seek: dateTime);
    } on DioException catch (e) {
      log.error('getGalleriesFailed'.tr, e.errorMsg);
      snack('getGalleriesFailed'.tr, e.errorMsg ?? '', isShort: true);
      state.loadingState = LoadingState.error;
      updateSafely([loadingStateId]);
      return;
    } on EHSiteException catch (e) {
      log.error('getGalleriesFailed'.tr, e.message);
      snack(
        'getGalleriesFailed'.tr,
        e.message,
        isShort: true,
        onPressed: e.referLink == null ? null : () => launchUrlString(e.referLink!, mode: LaunchMode.externalApplication),
      );
      state.loadingState = LoadingState.error;
      updateSafely([loadingStateId]);
      return;
    } catch (e) {
      log.error('getGalleriesFailed'.tr, e.toString());
      snack('getGalleriesFailed'.tr, e.toString(), isShort: true);
      updateSafely([loadingStateId]);
      return;
    }

    List<Gallery> galleries = await postHandleNewGalleries(galleryPage.galleries);

    state.galleries = galleries;
    state.totalCount = galleryPage.totalCount;
    state.prevGid = galleryPage.prevGid;
    state.nextGid = galleryPage.nextGid;
    state.favoriteSortOrder = galleryPage.favoriteSortOrder;
    state.galleryCollectionKey = Key(newUUID());

    state.seek = dateTime;

    if (state.nextGid == null && state.prevGid == null && state.galleries.isEmpty) {
      state.loadingState = LoadingState.noData;
    } else if (state.nextGid == null) {
      state.loadingState = LoadingState.noMore;
    } else {
      state.loadingState = LoadingState.idle;
    }

    updateSafely();
  }

  Future<void> handleTapJumpButton() async {
    DateTime? dateTime = await showDatePicker(
      context: Get.context!,
      initialDate: state.seek,
      currentDate: DateTime.now(),
      firstDate: DateTime(2007),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );

    if (dateTime != null) {
      jumpPage(dateTime);
    }
  }

  Future<void> handleTapFilterButton([EHSearchConfigDialogType searchConfigDialogType = EHSearchConfigDialogType.filter]) async {
    await state.searchConfigInitCompleter.future;

    Map<String, dynamic>? result = await Get.dialog(
      EHSearchConfigDialog(searchConfig: state.searchConfig, type: searchConfigDialogType),
    );

    if (result == null) {
      return;
    }

    SearchConfig searchConfig = result['searchConfig'];
    state.searchConfig = searchConfig;

    /// No need to save at search page
    if (useSearchConfig) {
      await saveSearchConfig(searchConfig);
    }

    handleClearAndRefresh();
  }

  void handleTapGalleryCard(Gallery gallery) async {
    /// The external source has its own, lighter detail page.
    if (gallery.galleryUrl.source == GallerySource.xlecx) {
      toRoute(
        Routes.xlecxDetails,
        arguments: gallery,
      );
      return;
    }

    toRoute(
      Routes.details,
      arguments: DetailsPageArgument(galleryUrl: gallery.galleryUrl, gallery: gallery),
    );
  }

  void handleLongPressCard(BuildContext context, Gallery gallery, {Offset? position}) async {}

  void handleSecondaryTapCard(BuildContext context, Gallery gallery, {Offset? position}) async {}

  Future<GalleryPageInfo> getGalleryPage({String? prevGid, String? nextGid, DateTime? seek}) async {
    log.info('$runtimeType get data, prevGid:$prevGid, nextGid:$nextGid');

    await state.searchConfigInitCompleter.future;

    return ehRequest.requestGalleryPage(
      prevGid: prevGid,
      nextGid: nextGid,
      seek: seek,
      searchConfig: state.searchConfig,
      parser: EHSpiderParser.galleryPage2GalleryPageInfo,
    );
  }

  /// Wraps [getGalleryPage] so a page made only of already-read galleries is
  /// skipped instead of leaving an empty list (and a stuck infinite scroll).
  ///
  /// Jumps by date (`seek`) are left untouched.
  Future<GalleryPageInfo> _getGalleryPageSkippingHidden({String? prevGid, String? nextGid, DateTime? seek}) async {
    GalleryPageInfo page = await getGalleryPage(prevGid: prevGid, nextGid: nextGid, seek: seek);

    if (!hideAlreadyReadGalleries || seek != null) {
      return page;
    }

    int attempts = 0;
    while (attempts < 5 &&
        page.galleries.isNotEmpty &&
        page.galleries.every((gallery) => alreadyReadService.contains(gallery.gid))) {
      if (prevGid != null) {
        if (page.prevGid == null) {
          break;
        }
        page = await getGalleryPage(prevGid: page.prevGid);
      } else {
        if (page.nextGid == null) {
          break;
        }
        page = await getGalleryPage(nextGid: page.nextGid);
      }
      attempts++;
    }

    return page;
  }

  Future<void> saveSearchConfig(SearchConfig searchConfig) async {
    await localConfigService.write(
      configKey: ConfigEnum.searchConfig,
      subConfigKey: searchConfigKey,
      value: jsonEncode(searchConfig),
    );
  }

  Future<List<Gallery>> postHandleNewGalleries(List<Gallery> galleries, {bool cleanDuplicate = true}) async {
    if (cleanDuplicate) {
      _cleanDuplicateGallery(galleries);
    }

    await _translateGalleryTagsIfNeeded(galleries);
    await readProgressService.preloadReadProgress(galleries.map((gallery) => gallery.gid));

    List<Gallery> filteredGalleries = await _filterByBlockingRules(galleries);

    if (hideAlreadyReadGalleries) {
      filteredGalleries = filteredGalleries.where((gallery) => !alreadyReadService.contains(gallery.gid)).toList();
    }

    if (preferenceSetting.preloadGalleryCover.isTrue) {
      for (Gallery gallery in galleries) {
        getNetworkImageData(gallery.cover.url, useCache: true);
      }
    }

    return filteredGalleries;
  }

  /// deal with the first and last page
  void _cleanDuplicateGallery(List<Gallery> newGalleries) {
    newGalleries.removeWhere((newGallery) => state.galleries.firstWhereOrNull((e) => e.galleryUrl == newGallery.galleryUrl) != null);
  }

  Future<List<Gallery>> _filterByBlockingRules(List<Gallery> newGalleries) async {
    if (newGalleries.isEmpty) {
      return newGalleries;
    }

    // if all galleries are filtered, we keep the first one to indicate it
    List<Gallery> filteredGalleries = await localBlockRuleService.executeRules(newGalleries);
    if (filteredGalleries.isNotEmpty) {
      return filteredGalleries;
    } else {
      return newGalleries.sublist(0, 1).map((g) => g..blockedByLocalRules = true).toList();
    }
  }

  Future<void> _translateGalleryTagsIfNeeded(List<Gallery> galleries) async {
    if (galleries.isEmpty) {
      return;
    }
    // One batched lookup for the whole page instead of one per gallery tag.
    final LinkedHashMap<String, List<GalleryTag>> merged = LinkedHashMap<String, List<GalleryTag>>();
    for (final Gallery gallery in galleries) {
      gallery.tags.forEach((namespace, tags) {
        (merged[namespace] ??= <GalleryTag>[]).addAll(tags);
      });
    }
    if (merged.isEmpty) {
      return;
    }
    await tagTranslationService.translateTagsIfNeeded(merged);
  }
}
