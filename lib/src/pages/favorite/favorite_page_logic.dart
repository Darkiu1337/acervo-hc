import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/extension/dio_exception_extension.dart';
import 'package:acervo_hc/src/extension/get_logic_extension.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';
import 'package:acervo_hc/src/model/gallery_page.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/network/eh_request.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/setting/user_setting.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/eh_alert_dialog.dart';
import 'package:acervo_hc/src/widget/eh_client_filter_dialog.dart';
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
  Timer? _localSearchDebounce;

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

    /// Keep the local list in sync when favorites or collections mutate from
    /// any page.
    _favoritesWorker = ever(localFavoriteService.revision, (_) {
      if (state.localMode) {
        if (state.selectedCollection != null && !localFavoriteService.collections.contains(state.selectedCollection)) {
          state.selectedCollection = null;
        }
        _loadLocalFavorites(scrollToTop: false);
      }
    });

    if (state.localMode) {
      _loadLocalFavorites(scrollToTop: false);
    }
  }

  @override
  void onClose() {
    _localSearchDebounce?.cancel();
    _favoritesWorker?.dispose();
    state.localSearchController.dispose();
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
    final List<Gallery> allInScope = localFavoriteService.favoritesInCollection(state.selectedCollection);
    state.totalLocalCount = localFavoriteService.favorites.length;

    final List<Gallery> filtered = state.localFilter.apply(allInScope);

    state.galleries
      ..clear()
      ..addAll(filtered);

    state.totalCount = null;
    state.prevGid = null;
    state.nextGid = null;
    state.loadingState = filtered.isEmpty ? LoadingState.noData : LoadingState.noMore;
    state.galleryCollectionKey = Key(newUUID());

    if (scrollToTop) {
      jump2Top();
    }

    updateSafely();
  }

  void selectLocalCollection(String? collectionName) {
    if (state.selectedCollection == collectionName) {
      return;
    }
    state.selectedCollection = collectionName;
    _loadLocalFavorites();
  }

  void onLocalSearchChanged(String value) {
    _localSearchDebounce?.cancel();
    _localSearchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (isClosed) {
        return;
      }
      state.localFilter = state.localFilter.copyWith(keyword: value.trim());
      _loadLocalFavorites();
    });
  }

  void clearLocalSearch() {
    _localSearchDebounce?.cancel();
    state.localSearchController.clear();
    state.localFilter = state.localFilter.copyWith(keyword: '');
    _loadLocalFavorites();
  }

  void selectLocalSource(GallerySource? source) {
    final Set<GallerySource> next = source == null
        ? const <GallerySource>{}
        : (state.localFilter.sources.length == 1 && state.localFilter.sources.contains(source)
            ? const <GallerySource>{}
            : <GallerySource>{source});
    state.localFilter = state.localFilter.copyWith(sources: next);
    _loadLocalFavorites();
  }

  void setLocalSortOrder(GallerySortOption order) {
    if (state.localFilter.sortOrder == order) {
      return;
    }
    state.localFilter = state.localFilter.copyWith(sortOrder: order);
    _loadLocalFavorites();
  }

  Future<void> handleTapLocalFilterButton() async {
    final GalleryClientFilter? result = await Get.dialog<GalleryClientFilter>(
      EHClientFilterDialog(
        initialFilter: state.localFilter,
        showSourceFilter: true,
        showSortOption: true,
      ),
    );
    if (result == null) {
      return;
    }
    state.localFilter = result;
    if (state.localSearchController.text != result.keyword) {
      state.localSearchController.text = result.keyword;
    }
    _loadLocalFavorites();
  }

  void clearLocalFilters() {
    _localSearchDebounce?.cancel();
    state.localSearchController.clear();
    state.selectedCollection = null;
    state.localFilter = const GalleryClientFilter();
    _loadLocalFavorites();
  }

  Future<void> handleCreateCollection() async {
    final TextEditingController controller = TextEditingController();
    final String? name = await Get.dialog<String>(
      AlertDialog(
        title: Text('createCollection'.tr),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'collectionNameHint'.tr,
            isDense: true,
          ),
          onSubmitted: (String value) => Navigator.of(Get.context!).pop(value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(Get.context!).pop(), child: Text('cancel'.tr)),
          FilledButton(
            onPressed: () => Navigator.of(Get.context!).pop(controller.text.trim()),
            child: Text('OK'.tr),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.isEmpty) {
      return;
    }

    final bool created = await localFavoriteService.createCollection(name);
    if (!created) {
      toast('collectionAlreadyExists'.tr);
    }
  }

  Future<void> handleManageCollectionMenu(BuildContext context, String collectionName, {Offset? position}) async {
    showEHContextMenu(
      context,
      position: position,
      actions: [
        EHContextMenuAction(
          text: 'rename'.tr,
          icon: const Icon(Icons.edit_outlined, size: 18),
          onTap: () => _handleRenameCollection(collectionName),
        ),
        EHContextMenuAction(
          text: 'delete'.tr,
          icon: const Icon(Icons.delete_outline, size: 18),
          color: UIConfig.alertColor(context),
          onTap: () => _handleDeleteCollection(collectionName),
        ),
      ],
    );
  }

  Future<void> _handleRenameCollection(String oldName) async {
    final TextEditingController controller = TextEditingController(text: oldName);
    final String? newName = await Get.dialog<String>(
      AlertDialog(
        title: Text('renameCollection'.tr),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(isDense: true, hintText: 'collectionNameHint'.tr),
          onSubmitted: (String value) => Navigator.of(Get.context!).pop(value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(Get.context!).pop(), child: Text('cancel'.tr)),
          FilledButton(
            onPressed: () => Navigator.of(Get.context!).pop(controller.text.trim()),
            child: Text('OK'.tr),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null || newName.isEmpty || newName == oldName) {
      return;
    }

    final bool renamed = await localFavoriteService.renameCollection(oldName, newName);
    if (renamed) {
      if (state.selectedCollection == oldName) {
        state.selectedCollection = newName;
      }
      _loadLocalFavorites(scrollToTop: false);
    } else {
      toast('collectionAlreadyExists'.tr);
    }
  }

  Future<void> _handleDeleteCollection(String name) async {
    final bool? confirmed = await Get.dialog<bool>(
      EHDialog(title: '${'delete'.tr} "$name"?'),
    );
    if (confirmed != true) {
      return;
    }

    if (state.selectedCollection == name) {
      state.selectedCollection = null;
    }
    await localFavoriteService.deleteCollection(name);
  }

  Future<void> handleAssignGalleryCollections(Gallery gallery) async {
    final Set<String> selected = Set<String>.from(localFavoriteService.collectionsOf(gallery.gid));
    final TextEditingController newColController = TextEditingController();

    final Set<String>? result = await Get.dialog<Set<String>>(
      StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setState) {
          final List<String> allCollections = List<String>.of(localFavoriteService.collections);
          for (final String col in selected) {
            if (!allCollections.contains(col)) {
              allCollections.add(col);
            }
          }

          return AlertDialog(
            title: Text('manageCollections'.tr),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newColController,
                            decoration: InputDecoration(
                              hintText: 'createCollection'.tr,
                              isDense: true,
                            ),
                            onSubmitted: (String value) {
                              final String trimmed = value.trim();
                              if (trimmed.isNotEmpty) {
                                setState(() {
                                  selected.add(trimmed);
                                  newColController.clear();
                                });
                              }
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'createCollection'.tr,
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final String trimmed = newColController.text.trim();
                            if (trimmed.isNotEmpty) {
                              setState(() {
                                selected.add(trimmed);
                                newColController.clear();
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (allCollections.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('noCollectionsYet'.tr, style: Theme.of(context).textTheme.bodySmall),
                      )
                    else
                      ...allCollections.map(
                        (String col) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(col),
                          value: selected.contains(col),
                          onChanged: (bool? checked) {
                            setState(() {
                              if (checked ?? false) {
                                selected.add(col);
                              } else {
                                selected.remove(col);
                              }
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('cancel'.tr)),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(Set<String>.from(selected)),
                child: Text('OK'.tr),
              ),
            ],
          );
        },
      ),
    );
    newColController.dispose();

    if (result != null) {
      await localFavoriteService.setGalleryCollections(gallery.gid, result);
    }
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
          text: 'manageCollections'.tr,
          icon: const Icon(Icons.folder_outlined, size: 18),
          onTap: () => handleAssignGalleryCollections(gallery),
        ),
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
