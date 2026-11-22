import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/storage_service.dart';
import 'package:acervo_hc/src/utils/cover_hash_util.dart';
import 'package:acervo_hc/src/utils/gallery_identity_matcher.dart';

AlreadyReadService alreadyReadService = AlreadyReadService();

/// Galleries manually marked as "already read".
///
/// The list has two roles:
///  1. it hides the gallery from the listing pages (home, search, popular,
///     watched and the Xlecx source) — including cross-provider duplicates
///     between E-Hentai/ExHentai and Xlecx — so already seen works do not come
///     back on either provider;
///  2. it is the source of the "Already read" page in the sidebar, where they
///     can be inspected and removed.
///
/// Cross-provider deduplication uses a two-tier multi-signal strategy:
///  - Tier 1 (synchronous, sub-millisecond): strict normalized title variants
///    (handling brackets and bilingual separators) + sequel/chapter numeric
///    guards + page-count compatibility + creator/artist corroboration.
///  - Tier 2 (asynchronous, cache-first): 128-bit perceptual cover dHash
///    matching for galleries whose titles differ across providers or are too
///    short/generic to match safely by metadata alone.
class AlreadyReadService {
  static const String _storageKey = 'alreadyReadGalleries';

  /// Rows per page of the "Already read" page.
  static const int pageSize = 100;

  /// Max concurrent cover hash decodes for background visual deduplication.
  static const int _maxVisualConcurrency = 3;

  final RxList<GalleryHistoryModel> galleries = <GalleryHistoryModel>[].obs;

  /// gids in [galleries], for fast checks while filtering listings/cards.
  final RxSet<int> gids = <int>{}.obs;

  /// Bumped whenever the already-read set or discovered cross-provider matches
  /// change so listings and detail buttons stay in sync.
  final RxInt revision = 0.obs;

  bool _restored = false;
  bool _backfillStarted = false;

  /// Per-provider normalized identities for fast 3-way cross-provider checks
  /// (E-Hentai/ExHentai <-> Xlecx <-> nhentai).
  final Map<GallerySource, List<GalleryIdentity>> _identitiesBySource = <GallerySource, List<GalleryIdentity>>{
    for (final GallerySource source in GallerySource.values) source: <GalleryIdentity>[],
  };

  /// Exact-variant lookup indexes per provider (`variant.comparable -> identities`)
  /// to keep Tier 1 matching near O(1) even with large already-read lists.
  final Map<GallerySource, Map<String, List<GalleryIdentity>>> _titleIndexBySource =
      <GallerySource, Map<String, List<GalleryIdentity>>>{
    for (final GallerySource source in GallerySource.values) source: <String, List<GalleryIdentity>>{},
  };

  /// Maps a cross-provider matched gallery's gid -> the gid of the stored
  /// already-read entry that matched it.
  final Map<int, int> _crossMatchedToSource = <int, int>{};

  /// Tracks visual check state per `(gid -> hashEpoch)` so each visible card
  /// is hashed at most once until new opposing cover hashes arrive.
  final Map<int, int> _visuallyCheckedEpoch = <int, int>{};
  int _hashEpoch = 0;

  /// Pending background visual dedup queue.
  final Queue<Gallery> _visualQueue = Queue<Gallery>();
  final Set<int> _visualQueuedGids = <int>{};
  int _visualInFlight = 0;

  /// Debounced persistence when backfilling cover hashes.
  Timer? _persistTimer;

  int get count => galleries.length;

  /// Loads the stored list once, before the first read from a build.
  void ensureRestored() {
    if (_restored) {
      return;
    }
    _restored = true;

    try {
      final String? raw = storageService.read<String>(_storageKey);
      if (raw == null || raw.isEmpty) {
        return;
      }

      final List<dynamic> decoded = jsonDecode(raw) as List;
      for (final dynamic entry in decoded) {
        try {
          final GalleryHistoryModel gallery = GalleryHistoryModel.fromJson(Map<String, dynamic>.from(entry as Map));
          galleries.add(gallery);
          gids.add(gallery.galleryUrl.gid);
        } catch (e) {
          log.error('Restore already-read entry failed', e);
        }
      }
      _rebuildIndexes();
      _scheduleBackfillMissingHashes();
    } catch (e) {
      log.error('Restore already-read galleries failed', e);
    }
  }

  /// True when [gid] is directly marked as read OR has already been matched
  /// against an already-read entry from the other provider.
  bool contains(int gid) {
    ensureRestored();
    revision.value;
    return gids.contains(gid) || _crossMatchedToSource.containsKey(gid);
  }

  /// Synchronous check for listings and detail views: checks exact gid,
  /// previously discovered visual matches, and Tier 1 multi-signal metadata
  /// matching against the opposing provider.
  bool isAlreadyRead(Gallery gallery) {
    ensureRestored();
    revision.value;

    final int gid = gallery.gid;
    if (gids.contains(gid) || _crossMatchedToSource.containsKey(gid)) {
      return true;
    }

    final int? matchedSourceGid = _matchTier1(gallery);
    if (matchedSourceGid != null) {
      _crossMatchedToSource[gid] = matchedSourceGid;
      return true;
    }

    return false;
  }

  /// Returns the stored [GalleryHistoryModel] matching [gallery] (either exact
  /// gid or cross-provider counterpart), or `null` if not read.
  GalleryHistoryModel? findMatchingEntry(Gallery gallery) {
    ensureRestored();
    revision.value;

    final int gid = gallery.gid;
    final int? sourceGid = gids.contains(gid)
        ? gid
        : (_crossMatchedToSource[gid] ?? _matchTier1(gallery));
    if (sourceGid == null) {
      return null;
    }
    if (sourceGid != gid) {
      _crossMatchedToSource[gid] = sourceGid;
    }
    return _findByGid(sourceGid);
  }

  /// Returns the stored entry matching [gid] (exact or cached cross-match).
  GalleryHistoryModel? findMatchingEntryByGid(int gid) {
    ensureRestored();
    revision.value;

    final int? sourceGid = gids.contains(gid) ? gid : _crossMatchedToSource[gid];
    return sourceGid == null ? null : _findByGid(sourceGid);
  }

  /// Schedules lightweight background Tier 2 (perceptual cover hash) checks for
  /// visible listing cards that were not already caught by Tier 1.
  ///
  /// Does nothing when the opposing provider has no hashed already-read entries
  /// with a compatible page count.
  void scheduleVisualDeduplication(Iterable<Gallery> candidates) {
    ensureRestored();

    for (final Gallery gallery in candidates) {
      final int gid = gallery.gid;
      if (gallery.cover.url.trim().isEmpty) {
        continue;
      }
      if (gids.contains(gid) || _crossMatchedToSource.containsKey(gid)) {
        continue;
      }
      if (_visuallyCheckedEpoch[gid] == _hashEpoch || _visualQueuedGids.contains(gid)) {
        continue;
      }
      if (!_hasPotentialVisualCandidate(gallery)) {
        _visuallyCheckedEpoch[gid] = _hashEpoch;
        continue;
      }

      _visualQueuedGids.add(gid);
      _visualQueue.add(gallery);
    }

    _pumpVisualQueue();
  }

  /// Checks whether a [GalleryHistoryModel] (e.g. built from a detail page
  /// opened via direct link) is already read directly or via a cross-provider
  /// counterpart.
  bool isHistoryModelAlreadyRead(GalleryHistoryModel model) {
    ensureRestored();
    revision.value;

    final int gid = model.galleryUrl.gid;
    if (gids.contains(gid) || _crossMatchedToSource.containsKey(gid)) {
      return true;
    }

    final int? matchedSourceGid = _matchTier1Identity(GalleryIdentity.fromHistoryModel(model));
    if (matchedSourceGid != null) {
      _crossMatchedToSource[gid] = matchedSourceGid;
      return true;
    }

    return false;
  }

  /// Returns `true` when the gallery is marked as read after this call.
  ///
  /// When toggling a gallery that is matched via a cross-provider counterpart,
  /// removes that counterpart so the gallery becomes unread on both providers.
  Future<bool> toggle(GalleryHistoryModel gallery) async {
    ensureRestored();
    final int gid = gallery.galleryUrl.gid;

    if (gids.contains(gid)) {
      await remove(gid);
      return false;
    }

    final int? crossSourceGid =
        _crossMatchedToSource[gid] ?? _matchTier1Identity(GalleryIdentity.fromHistoryModel(gallery));
    if (crossSourceGid != null && gids.contains(crossSourceGid)) {
      await remove(crossSourceGid);
      return false;
    }

    await add(gallery);
    return true;
  }

  Future<void> add(GalleryHistoryModel gallery) async {
    ensureRestored();

    final List<GalleryHistoryModel> next = List<GalleryHistoryModel>.of(galleries);
    next.removeWhere((GalleryHistoryModel e) => e.galleryUrl.gid == gallery.galleryUrl.gid);
    next.insert(0, gallery);

    /// Update both stores before notifying, and notify exactly once: listeners
    /// reload synchronously, so they must observe the final list (the first
    /// notification of a remove-then-insert sequence used to be delivered while
    /// the new gallery was still missing).
    gids.add(gallery.galleryUrl.gid);
    galleries.value = next;
    _rebuildIndexes();
    revision.value++;

    await _persist();

    if (gallery.coverHash == null && gallery.coverUrl.trim().isNotEmpty) {
      unawaited(_computeAndStoreEntryHash(gallery.galleryUrl.gid));
    }
  }

  Future<void> remove(int gid) async {
    ensureRestored();
    final int targetGid = gids.contains(gid) ? gid : (_crossMatchedToSource[gid] ?? gid);
    if (!gids.contains(targetGid)) {
      return;
    }

    final List<GalleryHistoryModel> next = List<GalleryHistoryModel>.of(galleries)
      ..removeWhere((GalleryHistoryModel e) => e.galleryUrl.gid == targetGid);

    gids.remove(targetGid);
    _crossMatchedToSource.removeWhere((int candidateGid, int sourceGid) => sourceGid == targetGid || candidateGid == targetGid);
    galleries.value = next;
    _rebuildIndexes();
    revision.value++;

    await _persist();
  }

  Future<void> clear() async {
    ensureRestored();
    gids.clear();
    _crossMatchedToSource.clear();
    _visuallyCheckedEpoch.clear();
    _visualQueue.clear();
    _visualQueuedGids.clear();
    galleries.value = <GalleryHistoryModel>[];
    _rebuildIndexes();
    revision.value++;
    await _persist();
  }

  int getPageCount() {
    ensureRestored();
    return galleries.isEmpty ? 0 : (galleries.length - 1) ~/ pageSize + 1;
  }

  List<GalleryHistoryModel> getByPageIndex(int pageIndex) {
    ensureRestored();
    return galleries.skip(pageIndex * pageSize).take(pageSize).toList();
  }

  GalleryHistoryModel? _findByGid(int gid) {
    for (final GalleryHistoryModel entry in galleries) {
      if (entry.galleryUrl.gid == gid) {
        return entry;
      }
    }
    return null;
  }

  void _rebuildIndexes() {
    for (final GallerySource source in GallerySource.values) {
      _identitiesBySource[source]!.clear();
      _titleIndexBySource[source]!.clear();
    }

    for (final GalleryHistoryModel entry in galleries) {
      final GalleryIdentity identity = GalleryIdentity.fromHistoryModel(entry);
      final List<GalleryIdentity> list = _identitiesBySource[identity.source]!;
      final Map<String, List<GalleryIdentity>> titleIndex = _titleIndexBySource[identity.source]!;

      list.add(identity);
      for (final TitleVariant variant in identity.titleVariants) {
        (titleIndex[variant.comparable] ??= <GalleryIdentity>[]).add(identity);
      }
    }
  }

  Iterable<GallerySource> _opposingSources(GallerySource source) {
    return GallerySource.values.where((GallerySource other) => other != source);
  }

  int? _matchTier1(Gallery gallery) {
    return _matchTier1Identity(GalleryIdentity.fromGallery(gallery));
  }

  int? _matchTier1Identity(GalleryIdentity candidate) {
    final Set<int> checked = <int>{};

    /// Fast path: check exact normalized title-variant hits across all other
    /// providers first in O(1).
    for (final GallerySource otherSource in _opposingSources(candidate.source)) {
      final Map<String, List<GalleryIdentity>> titleIndex = _titleIndexBySource[otherSource]!;
      if (titleIndex.isEmpty) {
        continue;
      }
      for (final TitleVariant variant in candidate.titleVariants) {
        final List<GalleryIdentity>? bucket = titleIndex[variant.comparable];
        if (bucket == null) {
          continue;
        }
        for (final GalleryIdentity entry in bucket) {
          if (!checked.add(entry.gid)) {
            continue;
          }
          if (GalleryIdentityMatcher.match(candidate, entry) != null) {
            return entry.gid;
          }
        }
      }
    }

    /// Fallback for fuzzy title + creator matches (only when candidate has
    /// creators; without creators, Tier 1 cannot accept fuzzy titles anyway).
    if (candidate.creators.isNotEmpty) {
      for (final GallerySource otherSource in _opposingSources(candidate.source)) {
        for (final GalleryIdentity entry in _identitiesBySource[otherSource]!) {
          if (!checked.add(entry.gid) || entry.creators.isEmpty) {
            continue;
          }
          if (GalleryIdentityMatcher.match(candidate, entry) != null) {
            return entry.gid;
          }
        }
      }
    }

    return null;
  }

  bool _hasPotentialVisualCandidate(Gallery gallery) {
    final int? pages = (gallery.pageCount != null && gallery.pageCount! > 0) ? gallery.pageCount : null;
    for (final GallerySource otherSource in _opposingSources(gallery.galleryUrl.source)) {
      for (final GalleryIdentity entry in _identitiesBySource[otherSource]!) {
        if (entry.coverHash != null && GalleryIdentityMatcher.arePageCountsCompatible(pages, entry.pageCount)) {
          return true;
        }
      }
    }
    return false;
  }

  void _pumpVisualQueue() {
    while (_visualInFlight < _maxVisualConcurrency && _visualQueue.isNotEmpty) {
      final Gallery gallery = _visualQueue.removeFirst();
      _visualQueuedGids.remove(gallery.gid);
      _visualInFlight++;
      unawaited(_runVisualCheck(gallery));
    }
  }

  Future<void> _runVisualCheck(Gallery gallery) async {
    final int gid = gallery.gid;
    final int epochAtStart = _hashEpoch;

    try {
      if (gids.contains(gid) || _crossMatchedToSource.containsKey(gid)) {
        return;
      }

      final CoverPerceptualHash? coverHash = await CoverHashUtil.computeForUrl(
        gallery.cover.url,
        allowNetwork: true,
      );
      _visuallyCheckedEpoch[gid] = epochAtStart;

      if (coverHash == null) {
        return;
      }

      final GalleryIdentity candidate = GalleryIdentity.fromGallery(gallery, coverHash: coverHash);
      for (final GallerySource otherSource in _opposingSources(candidate.source)) {
        for (final GalleryIdentity entry in _identitiesBySource[otherSource]!) {
          if (entry.coverHash == null) {
            continue;
          }
          final GalleryMatchResult? result = GalleryIdentityMatcher.match(candidate, entry);
          if (result != null) {
            _crossMatchedToSource[gid] = entry.gid;
            log.debug(
              'Cross-provider already-read match (${result.reason.name}, dist=${result.coverDistance}): '
              '${gallery.galleryUrl.url} <-> gid=${entry.gid}',
            );
            revision.value++;
            return;
          }
        }
      }
    } catch (e) {
      log.debug('Visual already-read dedup failed for gid=$gid: $e');
    } finally {
      _visualInFlight--;
      _pumpVisualQueue();
    }
  }

  Future<void> _computeAndStoreEntryHash(int gid) async {
    final GalleryHistoryModel? entry = _findByGid(gid);
    if (entry == null || entry.coverHash != null || entry.coverUrl.trim().isEmpty) {
      return;
    }

    final CoverPerceptualHash? hash = await CoverHashUtil.computeForUrl(
      entry.coverUrl,
      allowNetwork: true,
    );
    if (hash == null) {
      return;
    }

    final GalleryHistoryModel? current = _findByGid(gid);
    if (current == null || current.coverHash != null) {
      return;
    }

    current.coverHash = hash.toHex();
    _hashEpoch++;
    _rebuildIndexes();
    revision.value++;
    _scheduleDebouncedPersist();
  }

  /// Lazily computes cover hashes for existing already-read entries that were
  /// saved before perceptual deduplication existed. Runs gently one at a time
  /// so startup and scrolling stay completely unaffected.
  void _scheduleBackfillMissingHashes() {
    if (_backfillStarted) {
      return;
    }
    _backfillStarted = true;

    final List<int> missingGids = galleries
        .where((GalleryHistoryModel e) => e.coverHash == null && e.coverUrl.trim().isNotEmpty)
        .map((GalleryHistoryModel e) => e.galleryUrl.gid)
        .toList();
    if (missingGids.isEmpty) {
      return;
    }

    unawaited(Future<void>(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      for (final int gid in missingGids) {
        if (!gids.contains(gid)) {
          continue;
        }
        await _computeAndStoreEntryHash(gid);
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }));
  }

  void _scheduleDebouncedPersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() {
    _persistTimer?.cancel();
    return storageService.write(_storageKey, jsonEncode(galleries.toList()));
  }
}
