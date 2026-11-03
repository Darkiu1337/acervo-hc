import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/eight_muses_search.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/network/eight_muses_request.dart';
import 'package:acervo_hc/src/pages/eight_muses/eight_muses_state.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/eight_muses_catalog_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/utils/snack_util.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

/// Lists https://8muses.io galleries: listings, keyword search and tag search.
///
/// The site supports one exact tag per request (`/tag/<slug>`), so the first
/// included tag drives the request and every other filter (extra tags,
/// excluded tags, keyword) is applied locally on the fetched page. Tag/artist
/// pages carry the genres of each gallery; search result pages do not, which is
/// why keyword + tags always runs in tag mode.
class EightMusesLogic extends GetxController {
  final String bodyId = 'eightMusesBodyId';
  final String searchBarId = 'eightMusesSearchBarId';

  final EightMusesState state = EightMusesState();

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

  List<String> get recentSearches => eightMusesCatalogService.readRecentSearches();

  Future<void> removeRecentSearch(String keyword) async {
    await eightMusesCatalogService.removeRecentSearch(keyword);
    update([bodyId]);
  }

  Future<void> clearRecentSearches() async {
    await eightMusesCatalogService.clearRecentSearches();
    update([bodyId]);
  }

  List<EightMusesTag> get popularTags => eightMusesCatalogService.tags.take(12).toList();

  bool get loadingTags => eightMusesCatalogService.loadingTags;

  bool get hasTags => eightMusesCatalogService.tags.isNotEmpty;

  void _onFocusChanged() {
    if (state.showSuggestions == state.searchFocusNode.hasFocus) {
      return;
    }

    state.showSuggestions = state.searchFocusNode.hasFocus;
    update([bodyId, searchBarId]);

    if (state.showSuggestions) {
      eightMusesCatalogService.ensureTags().then((_) => update([bodyId]));
    }
  }

  Future<void> onRefresh() => refresh();

  Future<void> changeListing(EightMusesListing listing) async {
    if (state.listing == listing && !state.config.isSearching) {
      return;
    }

    state.listing = listing;
    state.config.reset();
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

    await eightMusesCatalogService.addRecentSearch(keyword);
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

  Future<void> toggleIncludeTag(EightMusesTag tag) async {
    if (state.config.includeTags.contains(tag)) {
      state.config.includeTags.remove(tag);
    } else {
      state.config.excludeTags.remove(tag);
      state.config.includeTags.add(tag);
    }

    _hideSuggestions();
    await refresh();
  }

  Future<void> toggleExcludeTag(EightMusesTag tag) async {
    if (state.config.excludeTags.contains(tag)) {
      state.config.excludeTags.remove(tag);
    } else {
      state.config.includeTags.remove(tag);
      state.config.excludeTags.add(tag);
    }

    _hideSuggestions();
    await refresh();
  }

  Future<void> applyConfig(EightMusesSearchConfig config) async {
    state.config.keyword = config.keyword.trim();
    state.config.includeTags
      ..clear()
      ..addAll(config.includeTags);
    state.config.excludeTags
      ..clear()
      ..addAll(config.excludeTags);
    state.config.artist = config.artist;
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

  /// Used by the gallery detail page: adds the tag to the current tag filter
  /// (additive, so clicking several tags intersects them instead of replacing).
  /// Keyword and the search-only options are cleared because tags drive the
  /// request and the extra filters do not apply to tag listings.
  Future<void> searchTag(EightMusesTag tag) async {
    state.config.excludeTags.remove(tag);
    if (!state.config.includeTags.contains(tag)) {
      state.config.includeTags.add(tag);
    }

    state.config.keyword = '';
    state.searchController.clear();
    state.config.sort = EightMusesSort.relevance;

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
    await eightMusesCatalogService.ensureTags(force: true);
    update([bodyId, searchBarId]);
  }

  /// Selects (or clears, when null) the artist whose listing is shown.
  Future<void> selectArtist(EightMusesTag? artist) async {
    if (state.config.artist == artist) {
      return;
    }

    state.config.artist = artist;
    state.config.keyword = '';
    state.searchController.clear();
    state.config.sort = EightMusesSort.relevance;

    _hideSuggestions();
    await refresh();
  }

  Future<void> setSort(EightMusesSort value) async {
    if (state.config.sort == value) {
      return;
    }
    state.config.sort = value;
    await refresh();
  }

  Future<void> refresh() async {
    _requestSerial++;
    state.nextPage = 1;
    state.scannedPages = 0;
    state.scannedCards = 0;
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

    final int expectedPageSize = _expectedPageSize;

    try {
      /// When filtering locally a whole page can be filtered out even though the
      /// site still has matches, so keep pulling pages until something survives
      /// (bounded to avoid hammering the site).
      int attempts = 0;
      while (attempts < 6) {
        attempts++;

        final List<Gallery> raw = await _fetchPage(state.nextPage);
        if (serial != _requestSerial) {
          return;
        }

        state.nextPage += 1;
        state.scannedPages += 1;
        state.scannedCards += raw.length;

        if (raw.isEmpty) {
          state.loadingState = state.galleries.isEmpty ? LoadingState.noData : LoadingState.noMore;
          break;
        }

        final List<Gallery> filtered = (state.config.isLocalFilterMode ? _applyLocalFilters(raw) : raw)
            .where((Gallery gallery) => !alreadyReadService.contains(gallery.gid))
            .toList();
        state.galleries.addAll(filtered);

        final bool isLastPage = raw.length < expectedPageSize;

        /// A page can disappear completely when every card is already read (or
        /// filtered out locally), so keep pulling pages until something is
        /// visible or the site runs out.
        if (filtered.isNotEmpty || isLastPage) {
          state.loadingState = isLastPage ? LoadingState.noMore : LoadingState.idle;
          break;
        }
      }

      if (state.loadingState == LoadingState.loading) {
        state.loadingState = state.galleries.isEmpty ? LoadingState.noData : LoadingState.idle;
      }
    } on DioException catch (e) {
      log.error('Load 8muses page failed', e.error);
      state.loadingState = LoadingState.error;
      snack('refreshGalleryFailed'.tr, e.message ?? '', isShort: true);
    } catch (e, s) {
      log.error('Load 8muses page failed', e, s);
      state.loadingState = LoadingState.error;
    }

    update([bodyId]);
  }

  int get _expectedPageSize => state.config.isLocalFilterMode || !state.config.isSearching ? 48 : 24;

  Future<List<Gallery>> _fetchPage(int page) {
    final EightMusesSearchConfig config = state.config;

    /// The artist listing is the most specific base, and its pages carry the
    /// genres of every gallery, so tags/keyword can still be applied locally.
    if (config.artist != null) {
      return eightMusesRequest.requestArtistPage(artistSlug: config.artist!.slug, page: page);
    }

    if (config.isTagMode) {
      return eightMusesRequest.requestTagPage(tagSlug: config.includeTags.first.slug, page: page);
    }

    if (config.hasKeyword) {
      return eightMusesRequest.search(config: config, page: page);
    }

    return eightMusesRequest.requestListing(listing: state.listing, page: page);
  }

  /// Applies the tags/keyword that the site request could not express.
  ///
  /// On a tag listing the first include tag is guaranteed by `/tag/<slug>`, so
  /// only the remaining ones are intersected here. On an artist listing every
  /// include tag is applied locally.
  List<Gallery> _applyLocalFilters(List<Gallery> galleries) {
    final EightMusesSearchConfig config = state.config;
    final List<String> includes = (config.isTagMode ? config.includeTags.skip(1) : config.includeTags)
        .map((EightMusesTag tag) => tag.normalizedLabel)
        .toList();
    final List<String> excludes = config.excludeTags.map((EightMusesTag tag) => tag.normalizedLabel).toList();
    final List<String> tokens = config.keyword
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((String token) => token.isNotEmpty)
        .toList();

    if (includes.isEmpty && excludes.isEmpty && tokens.isEmpty) {
      return galleries;
    }

    return galleries.where((Gallery gallery) {
      final Set<String> genres = gallery.externalTags.map(EightMusesTag.normalizeTagLabel).toSet();

      if (includes.any((String label) => !genres.contains(label))) {
        return false;
      }

      if (excludes.any(genres.contains)) {
        return false;
      }

      if (tokens.isNotEmpty) {
        final String haystack = '${gallery.title} ${gallery.uploader ?? ''}'.toLowerCase();
        if (!tokens.every(haystack.contains)) {
          return false;
        }
      }

      return true;
    }).toList();
  }
}
