import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/extension/dio_exception_extension.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_page.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/model/nhentai_gallery.dart';
import 'package:acervo_hc/src/model/search_config.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/network/eh_request.dart';
import 'package:acervo_hc/src/network/nhentai_request.dart';
import 'package:acervo_hc/src/network/xlecx_request.dart';
import 'package:acervo_hc/src/pages/multi_search/multi_search_state.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/utils/eh_spider_parser.dart';
import 'package:acervo_hc/src/utils/multi_search_matcher.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

class MultiSearchLogic extends GetxController {
  final String headerId = 'headerId';
  final String bodyId = 'bodyId';

  final MultiSearchState state = MultiSearchState();

  int _searchEpoch = 0;
  Worker? _alreadyReadWorker;
  Worker? _localFavWorker;

  @override
  void onInit() {
    super.onInit();
    alreadyReadService.ensureRestored();
    localFavoriteService.ensureRestored();

    _alreadyReadWorker = ever(alreadyReadService.revision, (_) {
      if (!isClosed && state.hasSearched) {
        update([headerId, bodyId]);
      }
    });
    _localFavWorker = ever(localFavoriteService.revision, (_) {
      if (!isClosed && state.hasSearched) {
        update([bodyId]);
      }
    });

    final dynamic arg = Get.arguments;
    if (arg is String && arg.trim().isNotEmpty) {
      state.searchController.text = arg.trim();
      Future.microtask(() => submitSearch(arg.trim()));
    }
  }

  @override
  void onClose() {
    _alreadyReadWorker?.dispose();
    _localFavWorker?.dispose();
    state.searchController.dispose();
    state.searchFocusNode.dispose();
    super.onClose();
  }

  void toggleSourceEnabled(GallerySource source) {
    if (state.enabledSources.contains(source)) {
      if (state.enabledSources.length <= 1) {
        return;
      }
      state.enabledSources.remove(source);
      if (state.activeTab == source) {
        state.activeTab = null;
      }
    } else {
      state.enabledSources.add(source);
    }
    update([headerId, bodyId]);
  }

  void toggleHideAlreadyRead() {
    state.hideAlreadyRead = !state.hideAlreadyRead;
    update([headerId, bodyId]);
  }

  void selectTab(GallerySource? tab) {
    if (state.activeTab == tab) {
      return;
    }
    state.activeTab = tab;
    update([headerId, bodyId]);
  }

  void clearSearch() {
    state.searchController.clear();
    state.query = '';
    state.hasSearched = false;
    state.crossMatches = <int, Set<GallerySource>>{};
    for (final SourceSearchBucket bucket in state.buckets.values) {
      bucket.reset();
    }
    update([headerId, bodyId]);
  }

  Future<void> submitSearch(String rawQuery) async {
    final String query = rawQuery.trim();
    if (query.isEmpty) {
      return;
    }

    state.searchFocusNode.unfocus();
    state.query = query;
    state.hasSearched = true;
    state.crossMatches = <int, Set<GallerySource>>{};
    final int epoch = ++_searchEpoch;

    for (final GallerySource source in GallerySource.values) {
      state.buckets[source]!.reset();
    }

    update([headerId, bodyId]);

    await Future.wait(
      state.enabledSources.map((GallerySource source) => _fetchSourcePage(source, epoch: epoch, loadMore: false)),
    );
  }

  Future<void> loadMoreForSource(GallerySource source) async {
    final SourceSearchBucket bucket = state.buckets[source]!;
    if (!bucket.hasMore || bucket.loadingState == LoadingState.loading) {
      return;
    }
    await _fetchSourcePage(source, epoch: _searchEpoch, loadMore: true);
  }

  Future<void> retrySource(GallerySource source) async {
    if (state.query.isEmpty) {
      return;
    }
    state.buckets[source]!.reset();
    await _fetchSourcePage(source, epoch: _searchEpoch, loadMore: false);
  }

  List<Gallery> visibleGalleriesFor(GallerySource source) {
    final List<Gallery> raw = state.buckets[source]!.galleries;
    if (!state.hideAlreadyRead) {
      return raw;
    }
    return raw.where((Gallery g) => !alreadyReadService.isAlreadyRead(g)).toList();
  }

  List<Gallery> visibleCombinedGalleries() {
    final Map<GallerySource, List<Gallery>> visibleBySource = <GallerySource, List<Gallery>>{
      for (final GallerySource source in state.enabledSources) source: visibleGalleriesFor(source),
    };
    return MultiSearchMatcher.interleaveResults(visibleBySource);
  }

  Future<void> _fetchSourcePage(
    GallerySource source, {
    required int epoch,
    required bool loadMore,
  }) async {
    final SourceSearchBucket bucket = state.buckets[source]!;
    bucket.loadingState = LoadingState.loading;
    bucket.errorMessage = null;
    update([headerId, bodyId]);

    try {
      final List<Gallery> fetched;
      bool hasMore = false;

      switch (source) {
        case GallerySource.eh:
          final GalleryPageInfo pageInfo = await ehRequest.requestGalleryPage<GalleryPageInfo>(
            searchConfig: SearchConfig(keyword: state.query),
            nextGid: loadMore ? bucket.ehNextGid : null,
            parser: EHSpiderParser.galleryPage2GalleryPageInfo,
          );
          fetched = pageInfo.galleries;
          bucket.ehNextGid = pageInfo.nextGid;
          hasMore = pageInfo.nextGid != null && fetched.isNotEmpty;
          break;

        case GallerySource.xlecx:
          final int page = loadMore ? bucket.nextPage : 1;
          final XlecxPage result = await xlecxRequest.search(
            config: XlecxSearchConfig(keyword: state.query),
            page: page,
          );
          fetched = result.galleries;
          bucket.nextPage = page + 1;
          hasMore = result.hasMore && fetched.isNotEmpty;
          break;

        case GallerySource.nhentai:
          final int page = loadMore ? bucket.nextPage : 1;
          final NHentaiSearchPage result = await nhentaiRequest.requestGalleries(
            page: page,
            sort: NHentaiSort.recent,
            language: NHentaiLanguage.all,
            query: state.query,
          );
          fetched = result.items.map((NHentaiGallerySummary item) => item.toGallery()).toList();
          bucket.nextPage = page + 1;
          hasMore = result.hasMore && fetched.isNotEmpty;
          break;
      }

      if (isClosed || epoch != _searchEpoch) {
        return;
      }

      final Set<int> existingGids = bucket.galleries.map((Gallery g) => g.gid).toSet();
      for (final Gallery g in fetched) {
        if (existingGids.add(g.gid)) {
          bucket.galleries.add(g);
        }
      }

      bucket.hasMore = hasMore;
      bucket.loadingState = bucket.galleries.isEmpty ? LoadingState.noData : LoadingState.success;

      _recomputeCrossMatches();
      alreadyReadService.scheduleVisualDeduplication(fetched);
      update([headerId, bodyId]);
    } on DioException catch (e) {
      if (isClosed || epoch != _searchEpoch) {
        return;
      }
      log.warning('MultiSearch ${source.name} failed: ${e.errorMsg ?? e.message}');
      bucket.errorMessage = e.errorMsg ?? e.message ?? 'failed'.tr;
      bucket.loadingState = LoadingState.error;
      update([headerId, bodyId]);
    } catch (e) {
      if (isClosed || epoch != _searchEpoch) {
        return;
      }
      log.warning('MultiSearch ${source.name} failed: $e');
      bucket.errorMessage = e.toString();
      bucket.loadingState = LoadingState.error;
      update([headerId, bodyId]);
    }
  }

  void _recomputeCrossMatches() {
    final Map<GallerySource, List<Gallery>> allBySource = <GallerySource, List<Gallery>>{
      for (final GallerySource source in state.enabledSources) source: state.buckets[source]!.galleries,
    };
    state.crossMatches = MultiSearchMatcher.findCrossProviderMatches(allBySource);
  }
}
