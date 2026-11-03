import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/network/xlecx_request.dart';
import 'package:acervo_hc/src/pages/xlecx/xlecx_state.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/xlecx_catalog_service.dart';
import 'package:acervo_hc/src/utils/snack_util.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

/// Lists https://xlecx.one galleries: the site's own listings (newest,
/// recently updated, top rated, most viewed, most commented), keyword search
/// and the category/tag/artist/parody filters.
///
/// Everything the site can filter by travels in the request path, so the tab
/// never filters pages locally (unlike the 8muses tab, whose cards carry the
/// genres). A keyword search is the only mode where the site ignores the other
/// filters, which is why the filter sheet disables them in that mode.
class XlecxLogic extends GetxController {
  final String bodyId = 'xlecxBodyId';
  final String searchBarId = 'xlecxSearchBarId';

  final XlecxState state = XlecxState();

  /// Lets a refresh invalidate in-flight page requests.
  int _requestSerial = 0;

  Worker? _alreadyReadWorker;

  @override
  void onInit() {
    super.onInit();

    localFavoriteService.ensureRestored();
    alreadyReadService.ensureRestored();

    /// Marking a card as already read removes it from the open grid.
    _alreadyReadWorker = ever(alreadyReadService.galleries, (_) {
      final int length = state.galleries.length;
      state.galleries.removeWhere((gallery) => alreadyReadService.contains(gallery.gid));

      if (state.galleries.length != length) {
        update([bodyId]);
      }
    });

    state.searchFocusNode.addListener(_onFocusChanged);
    loadMore();
  }

  @override
  void onClose() {
    _alreadyReadWorker?.dispose();
    state.searchFocusNode.removeListener(_onFocusChanged);
    state.searchFocusNode.dispose();
    state.searchController.dispose();
    state.scrollController.dispose();
    super.onClose();
  }

  List<String> get recentSearches => xlecxCatalogService.readRecentSearches();

  List<XlecxTag> get popularTags => xlecxCatalogService.tags.take(12).toList();

  bool get loadingTags => xlecxCatalogService.loadingTags;

  Future<void> removeRecentSearch(String keyword) async {
    await xlecxCatalogService.removeRecentSearch(keyword);
    update([bodyId]);
  }

  Future<void> clearRecentSearches() async {
    await xlecxCatalogService.clearRecentSearches();
    update([bodyId]);
  }

  void _onFocusChanged() {
    if (state.showSuggestions == state.searchFocusNode.hasFocus) {
      return;
    }

    state.showSuggestions = state.searchFocusNode.hasFocus;
    update([bodyId, searchBarId]);

    if (state.showSuggestions) {
      xlecxCatalogService.ensureTags().then((_) => update([bodyId]));
    }
  }

  Future<void> onRefresh() => refresh();

  /// Switches the listing preset (the site's sort keys) and drops the filters,
  /// like the 8muses listing tabs do.
  Future<void> changeListing(XlecxSort sort) async {
    if (state.config.sort == sort && !state.config.hasMediaFilters && !state.config.hasKeyword) {
      return;
    }

    state.config.reset();
    state.config.sort = sort;
    state.searchController.clear();
    _hideSuggestions();
    await refresh();
  }

  Future<void> submitKeyword(String value) async {
    final String keyword = value.trim();
    if (keyword.isEmpty) {
      await clearFilters();
      return;
    }

    state.config.keyword = keyword;
    state.searchController.text = keyword;
    state.searchFocusNode.unfocus();
    state.showSuggestions = false;

    await xlecxCatalogService.addRecentSearch(keyword);
    await refresh();
  }

  Future<void> clearKeyword() async {
    if (!state.config.hasKeyword) {
      return;
    }

    state.config.keyword = '';
    state.searchController.clear();
    await refresh();
  }

  Future<void> setCategory(XlecxCategory category) async {
    if (state.config.category == category) {
      return;
    }

    state.config.category = category;
    _hideSuggestions();
    await refresh();
  }

  Future<void> toggleIncludeTag(XlecxTag tag) async {
    if (state.config.includeTags.contains(tag)) {
      state.config.includeTags.remove(tag);
    } else {
      state.config.excludeTags.remove(tag);
      state.config.includeTags.add(tag);
    }

    _hideSuggestions();
    await refresh();
  }

  Future<void> toggleExcludeTag(XlecxTag tag) async {
    if (state.config.excludeTags.contains(tag)) {
      state.config.excludeTags.remove(tag);
    } else {
      state.config.includeTags.remove(tag);
      state.config.excludeTags.add(tag);
    }

    _hideSuggestions();
    await refresh();
  }

  Future<void> selectArtist(XlecxTag? artist) async {
    if (state.config.artist == artist) {
      return;
    }

    state.config.artist = artist;
    _hideSuggestions();
    await refresh();
  }

  Future<void> selectParody(XlecxTag? parody) async {
    if (state.config.parody == parody) {
      return;
    }

    state.config.parody = parody;
    _hideSuggestions();
    await refresh();
  }

  Future<void> selectGroup(XlecxTag? group) async {
    if (state.config.group == group) {
      return;
    }

    state.config.group = group;
    _hideSuggestions();
    await refresh();
  }

  Future<void> setSort(XlecxSort sort) async {
    if (state.config.sort == sort) {
      return;
    }

    state.config.sort = sort;
    await refresh();
  }

  Future<void> applyConfig(XlecxSearchConfig config) async {
    state.config.keyword = config.keyword.trim();
    state.config.includeTags
      ..clear()
      ..addAll(config.includeTags);
    state.config.excludeTags
      ..clear()
      ..addAll(config.excludeTags);
    state.config.artist = config.artist;
    state.config.parody = config.parody;
    state.config.group = config.group;
    state.config.category = config.category;
    state.config.sort = config.sort;

    _hideSuggestions();
    state.searchController.text = state.config.keyword;
    await refresh();
  }

  Future<void> clearFilters() async {
    state.config.reset();
    state.searchController.clear();
    _hideSuggestions();
    await refresh();
  }

  /// Used by the detail page chips: adds the tag/artist/parody to the current
  /// filter (additive, so clicking several tags intersects them) and clears the
  /// keyword, which would otherwise take over the request.
  Future<void> searchTag(XlecxTag tag) async {
    if (tag.kind == XlecxTagKind.artist) {
      state.config.artist = tag;
    } else if (tag.kind == XlecxTagKind.parody) {
      state.config.parody = tag;
    } else if (tag.kind == XlecxTagKind.group) {
      state.config.group = tag;
    } else {
      state.config.excludeTags.remove(tag);
      if (!state.config.includeTags.contains(tag)) {
        state.config.includeTags.add(tag);
      }
    }

    state.config.keyword = '';
    state.searchController.clear();

    _hideSuggestions();
    await refresh();
  }

  void _hideSuggestions() {
    if (state.searchFocusNode.hasFocus) {
      state.searchFocusNode.unfocus();
    }
    state.showSuggestions = false;
  }

  void hideSuggestions() {
    _hideSuggestions();
    update([bodyId]);
  }

  Future<void> reloadTags() async {
    await xlecxCatalogService.ensureTags(force: true);
    update([bodyId, searchBarId]);
  }

  Future<void> refresh() async {
    _requestSerial++;
    state.nextPage = 1;
    state.hasMore = true;
    state.galleries.clear();
    state.loadingState = LoadingState.idle;
    update([bodyId, searchBarId]);

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
      /// A whole page can disappear when every card is already read, so keep
      /// pulling pages until something survives (bounded to avoid hammering
      /// the site).
      int attempts = 0;
      while (attempts < 6) {
        attempts++;

        final XlecxPage page = await _fetchPage(state.nextPage);
        if (serial != _requestSerial) {
          return;
        }

        state.nextPage += 1;
        state.hasMore = page.hasMore;

        final List<Gallery> visible =
            page.galleries.where((Gallery gallery) => !alreadyReadService.contains(gallery.gid)).toList();
        state.galleries.addAll(visible);

        if (visible.isNotEmpty || !state.hasMore) {
          if (!state.hasMore) {
            state.loadingState = state.galleries.isEmpty ? LoadingState.noData : LoadingState.noMore;
          } else {
            state.loadingState = LoadingState.idle;
          }
          break;
        }
      }

      if (state.loadingState == LoadingState.loading) {
        state.loadingState = state.galleries.isEmpty ? LoadingState.noData : LoadingState.idle;
      }
    } on DioException catch (e) {
      log.error('Load Xlecx page failed', e.error);
      state.loadingState = LoadingState.error;
      snack('refreshGalleryFailed'.tr, _messageOf(e), isShort: true);
    } catch (e, s) {
      log.error('Load Xlecx page failed', e, s);
      state.loadingState = LoadingState.error;
    }

    update([bodyId]);
  }

  Future<XlecxPage> _fetchPage(int page) {
    if (state.config.hasKeyword) {
      return xlecxRequest.search(config: state.config, page: page);
    }

    return xlecxRequest.requestFiltered(config: state.config, page: page);
  }

  /// Refused pages are translated; anything else keeps the raw Dio message.
  String _messageOf(DioException e) => switch (XlecxRequest.errorMarkerOf(e)) {
        XlecxRequest.cloudflareErrorMarker => 'xlecxBlocked'.tr,
        XlecxRequest.restrictedErrorMarker => 'xlecxRestricted'.tr,
        XlecxRequest.notFoundErrorMarker => 'xlecxNotFound'.tr,
        _ => e.message ?? '',
      };
}
