import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/model/nhentai_gallery.dart';
import 'package:acervo_hc/src/network/nhentai_request.dart';
import 'package:acervo_hc/src/pages/nhentai/nhentai_state.dart';
import 'package:acervo_hc/src/routes/routes.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/setting/site_setting.dart';
import 'package:acervo_hc/src/utils/route_util.dart';
import 'package:acervo_hc/src/utils/snack_util.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

/// Controller for the dedicated nhentai tab powered by nhentai API v2.
class NHentaiLogic extends GetxController {
  final String bodyId = 'nhentaiBodyId';
  final String filterBarId = 'nhentaiFilterBarId';

  final NHentaiState state = NHentaiState();

  int _requestSerial = 0;
  Worker? _alreadyReadWorker;

  @override
  void onInit() {
    super.onInit();

    localFavoriteService.ensureRestored();
    alreadyReadService.ensureRestored();

    /// Marking a gallery as already read on E-Hentai, Xlecx, or nhentai
    /// removes matching cards live from this grid.
    _alreadyReadWorker = ever(alreadyReadService.revision, (_) {
      if (state.items.isEmpty) {
        return;
      }

      final int previousCount = state.items.length;
      state.items.removeWhere((NHentaiCardItem item) => alreadyReadService.isAlreadyRead(item.gallery));

      if (state.items.length != previousCount) {
        update([bodyId]);
      }

      if (state.items.isNotEmpty) {
        alreadyReadService.scheduleVisualDeduplication(state.items.map((NHentaiCardItem e) => e.gallery));
      }
    });

    loadMore();
  }

  @override
  void onClose() {
    _alreadyReadWorker?.dispose();
    state.searchFocusNode.dispose();
    state.searchController.dispose();
    state.scrollController.dispose();
    super.onClose();
  }

  Future<void> onRefresh() => refresh();

  Future<void> setSort(NHentaiSort sort) async {
    if (state.sort == sort) {
      return;
    }
    state.sort = sort;
    update([filterBarId]);
    await refresh();
  }

  Future<void> setLanguage(NHentaiLanguage language) async {
    if (state.language == language) {
      return;
    }
    state.language = language;
    update([filterBarId]);
    await refresh();
  }

  Future<void> submitSearch(String raw) async {
    final String trimmed = raw.trim();
    state.searchFocusNode.unfocus();

    /// Direct code jump: `#699178`, `699178`, or `https://nhentai.net/g/699178/`.
    final int? code = tryParseNHentaiCode(trimmed);
    if (code != null) {
      final GalleryUrl url = GalleryUrl.nhentaiGalleryUrl(code);
      toRoute(Routes.nhentaiDetails, arguments: nhentaiGalleryFromUrl(url));
      return;
    }

    state.query = trimmed;
    state.searchController.text = trimmed;
    update([filterBarId]);
    await refresh();
  }

  Future<void> clearSearch() async {
    if (state.query.isEmpty && state.searchController.text.isEmpty) {
      return;
    }
    state.query = '';
    state.searchController.clear();
    update([filterBarId]);
    await refresh();
  }

  /// Appends or runs a tag search from [NHentaiDetailsPage].
  Future<void> searchQuery(String query) async {
    final String trimmed = query.trim();
    state.query = trimmed;
    state.searchController.text = trimmed;
    state.searchFocusNode.unfocus();
    update([filterBarId]);
    await refresh();
  }

  Future<void> searchTag(NHentaiTag tag) {
    return searchQuery(tag.searchToken);
  }

  @override
  Future<void> refresh() async {
    _requestSerial++;
    state.nextPage = 1;
    state.hasMore = true;
    state.items.clear();
    state.loadingState = LoadingState.idle;
    update([bodyId, filterBarId]);

    await loadMore();
  }

  Future<void> loadMore() async {
    if (state.loadingState == LoadingState.loading || state.loadingState == LoadingState.noMore) {
      return;
    }

    final int serial = _requestSerial;
    state.loadingState = LoadingState.loading;
    update([bodyId]);

    try {
      /// If every item on a page is already read, fetch a few more pages
      /// politely (with a short pause to respect API v2 rate limits).
      int attempts = 0;
      while (attempts < 3) {
        if (attempts > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          if (serial != _requestSerial) {
            return;
          }
        }
        attempts++;

        final NHentaiSearchPage page = await nhentaiRequest.requestGalleries(
          page: state.nextPage,
          sort: state.sort,
          language: state.language,
          query: state.query,
        );
        if (serial != _requestSerial) {
          return;
        }

        state.nextPage += 1;
        state.hasMore = page.hasMore;

        final bool preferJp = SiteSetting.preferJapaneseTitle.isTrue;
        final List<NHentaiCardItem> visible = <NHentaiCardItem>[];
        for (final NHentaiGallerySummary summary in page.items) {
          final Gallery gallery = summary.toGallery(preferJapaneseTitle: preferJp);
          if (!alreadyReadService.isAlreadyRead(gallery)) {
            visible.add(NHentaiCardItem(gallery: gallery, numFavorites: summary.numFavorites));
          }
        }

        state.items.addAll(visible);
        if (visible.isNotEmpty) {
          alreadyReadService.scheduleVisualDeduplication(visible.map((NHentaiCardItem e) => e.gallery));
        }

        if (visible.isNotEmpty || !state.hasMore) {
          if (!state.hasMore) {
            state.loadingState = state.items.isEmpty ? LoadingState.noData : LoadingState.noMore;
          } else {
            state.loadingState = LoadingState.idle;
          }
          break;
        }
      }

      if (state.loadingState == LoadingState.loading) {
        state.loadingState = state.items.isEmpty ? LoadingState.noData : LoadingState.idle;
      }
    } on DioException catch (e) {
      log.error('Load nhentai page failed', e.error);
      state.loadingState = LoadingState.error;
      snack('refreshGalleryFailed'.tr, e.message ?? '${e.response?.statusCode ?? ''}', isShort: true);
    } catch (e, s) {
      log.error('Load nhentai page failed', e, s);
      state.loadingState = LoadingState.error;
    }

    update([bodyId]);
  }
}
