import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/widget/eh_alert_dialog.dart';
import 'package:acervo_hc/src/widget/eh_client_filter_dialog.dart';
import 'package:acervo_hc/src/widget/eh_context_menu.dart';

import '../../model/gallery.dart';
import '../../utils/convert_util.dart';
import '../base/old_base_page_logic.dart';
import 'already_read_page_state.dart';

/// Lists the galleries manually marked as "already read" (hidden from the
/// listing pages), with local search, provider source filter, and sorting.
class AlreadyReadPageLogic extends OldBasePageLogic {
  @override
  final AlreadyReadPageState state = AlreadyReadPageState();

  @override
  bool get useSearchConfig => false;

  /// This page exists to show them, so it must not hide them.
  @override
  bool get hideAlreadyReadGalleries => false;

  Worker? _alreadyReadWorker;
  Timer? _searchDebounce;

  @override
  Future<void> onInit() async {
    alreadyReadService.ensureRestored();
    await super.onInit();

    /// Keep the list in sync when a gallery is marked/unmarked from another
    /// page (details or card menu). Deferred to a microtask so the reload
    /// observes the list after the mutation completes.
    _alreadyReadWorker = ever(alreadyReadService.galleries, (_) {
      if (!isClosed) {
        Future.microtask(handleClearAndRefresh);
      }
    });
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    _alreadyReadWorker?.dispose();
    state.searchController.dispose();
    super.onClose();
  }

  @override
  Future<List<dynamic>> getGalleriesAndPageInfoByPage(int pageIndex) async {
    alreadyReadService.ensureRestored();
    final List<Gallery> allGalleries = alreadyReadService.galleries.map(galleryHistoryModel2Gallery).toList();
    state.totalStoredCount = allGalleries.length;

    final List<Gallery> filtered = state.clientFilter.apply(allGalleries);
    state.filteredTotalCount = filtered.length;

    final int pageCount = filtered.isEmpty ? 0 : (filtered.length - 1) ~/ AlreadyReadService.pageSize + 1;
    final List<Gallery> pageSlice = filtered
        .skip(pageIndex * AlreadyReadService.pageSize)
        .take(AlreadyReadService.pageSize)
        .toList();

    return [
      pageSlice,
      pageCount,
      pageIndex >= 1 ? pageIndex - 1 : null,
      pageIndex < pageCount - 1 ? pageIndex + 1 : null,
    ];
  }

  void onSearchKeywordChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (isClosed) {
        return;
      }
      state.clientFilter = state.clientFilter.copyWith(keyword: value.trim());
      handleClearAndRefresh();
    });
  }

  void clearSearchKeyword() {
    _searchDebounce?.cancel();
    state.searchController.clear();
    state.clientFilter = state.clientFilter.copyWith(keyword: '');
    handleClearAndRefresh();
  }

  void selectSingleSource(GallerySource? source) {
    final Set<GallerySource> next = source == null
        ? const <GallerySource>{}
        : (state.clientFilter.sources.length == 1 && state.clientFilter.sources.contains(source)
            ? const <GallerySource>{}
            : <GallerySource>{source});
    state.clientFilter = state.clientFilter.copyWith(sources: next);
    handleClearAndRefresh();
  }

  void setSortOrder(GallerySortOption order) {
    if (state.clientFilter.sortOrder == order) {
      return;
    }
    state.clientFilter = state.clientFilter.copyWith(sortOrder: order);
    handleClearAndRefresh();
  }

  Future<void> handleTapClientFilterButton() async {
    final GalleryClientFilter? result = await Get.dialog<GalleryClientFilter>(
      EHClientFilterDialog(
        initialFilter: state.clientFilter,
        showSourceFilter: true,
        showSortOption: true,
      ),
    );
    if (result == null) {
      return;
    }

    state.clientFilter = result;
    if (state.searchController.text != result.keyword) {
      state.searchController.text = result.keyword;
    }
    await handleClearAndRefresh();
  }

  void clearAllFilters() {
    _searchDebounce?.cancel();
    state.searchController.clear();
    state.clientFilter = const GalleryClientFilter();
    handleClearAndRefresh();
  }

  Future<void> handleTapDeleteButton() async {
    bool? result = await Get.dialog(EHDialog(title: '${'deleteAll'.tr}?'));

    if (result == true) {
      await alreadyReadService.clear();
    }
  }

  @override
  void handleLongPressCard(BuildContext context, Gallery gallery, {Offset? position}) {
    showEHContextMenu(
      context,
      position: position,
      actions: [
        EHContextMenuAction(
          text: 'removeFromAlreadyRead'.tr,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          color: UIConfig.alertColor(context),
          onTap: () => remove(gallery.gid),
        ),
      ],
    );
  }

  @override
  void handleSecondaryTapCard(BuildContext context, Gallery gallery, {Offset? position}) {
    handleLongPressCard(context, gallery, position: position);
  }

  Future<void> remove(int gid) async {
    await alreadyReadService.remove(gid);
  }
}
