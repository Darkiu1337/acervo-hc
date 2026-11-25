import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/service/isolate_service.dart';
import 'package:acervo_hc/src/service/jh_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/path_service.dart';
import 'package:acervo_hc/src/service/storage_service.dart';
import 'package:acervo_hc/src/utils/atomic_json_store.dart';

LocalFavoriteService localFavoriteService = LocalFavoriteService();

/// Local (offline) favorites for external sources (Xlecx, nhentai) and offline
/// bookmarks, with optional user-defined collections/folders.
///
/// Persisted atomically in `local_favorites.json` off the UI thread via
/// [AtomicJsonStore], with automatic one-time migration from legacy GetStorage.
class LocalFavoriteService with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String _legacyStorageKey = 'localFavorites';
  static const String _fileName = 'local_favorites.json';
  static const int _schemaVersion = 2;

  final AtomicJsonStore _store;

  LocalFavoriteService({AtomicJsonStore? store})
      : _store = store ??
            AtomicJsonStore(
              directoryProvider: () => pathService.getVisibleDir(),
              fileName: _fileName,
            );

  /// Newest first.
  final RxList<Gallery> favorites = <Gallery>[].obs;

  /// Ordered list of user-created collection names.
  final RxList<String> collections = <String>[].obs;

  /// Bumped whenever favorites or collection assignments change.
  final RxInt revision = 0.obs;

  final Map<int, List<String>> _galleryCollections = <int, List<String>>{};

  bool _restored = false;

  @override
  List<JHLifeCircleBean> get initDependencies =>
      super.initDependencies..addAll([pathService, storageService, isolateService]);

  @override
  Future<void> doInitBean() async {
    await restoreAsync();
  }

  @override
  Future<void> doAfterBeanReady() async {}

  /// Loads the stored favorites and collections asynchronously off the UI
  /// thread, migrating once from legacy GetStorage if needed.
  Future<void> restoreAsync() async {
    if (_restored) {
      return;
    }
    _restored = true;

    try {
      dynamic decoded = await _store.readJson();
      bool migratedFromLegacy = false;

      if (decoded == null) {
        final String? legacyRaw = _tryReadLegacyStorage();
        if (legacyRaw != null && legacyRaw.isNotEmpty) {
          decoded = await AtomicJsonStore.decodeJsonString(legacyRaw);
          migratedFromLegacy = true;
        }
      }

      if (decoded != null) {
        _applyDecodedPayload(decoded);
        if (migratedFromLegacy) {
          unawaited(_persist());
        }
      }
    } catch (e, s) {
      log.error('Restore local favorites async failed', e, s);
    }
  }

  /// Synchronous fallback when accessed before [doInitBean] (e.g. in tests).
  void ensureRestored() {
    if (_restored) {
      return;
    }
    _restored = true;

    try {
      dynamic decoded;
      bool migratedFromLegacy = false;
      try {
        decoded = _store.readJsonSync();
      } catch (_) {
        decoded = null;
      }

      if (decoded == null) {
        final String? legacyRaw = _tryReadLegacyStorage();
        if (legacyRaw != null && legacyRaw.isNotEmpty) {
          decoded = jsonDecode(legacyRaw);
          migratedFromLegacy = true;
        }
      }

      if (decoded != null) {
        _applyDecodedPayload(decoded);
        if (migratedFromLegacy) {
          unawaited(_persist());
        }
      }
    } catch (e) {
      log.error('Restore local favorites failed', e);
    }
  }

  String? _tryReadLegacyStorage() {
    try {
      return storageService.read<String>(_legacyStorageKey);
    } catch (_) {
      return null;
    }
  }

  void _applyDecodedPayload(dynamic decoded) {
    final List<Gallery> parsedFavorites = <Gallery>[];
    final Set<int> seenGids = <int>{};
    final List<String> parsedCollections = <String>[];
    final Map<int, List<String>> parsedAssignments = <int, List<String>>{};

    if (decoded is List) {
      for (final dynamic entry in decoded) {
        try {
          final Gallery gallery = Gallery.fromJson(Map<String, dynamic>.from(entry as Map));
          if (seenGids.add(gallery.gid)) {
            parsedFavorites.add(gallery);
          }
        } catch (e) {
          log.error('Restore local favorite entry failed', e);
        }
      }
    } else if (decoded is Map) {
      final List<dynamic> favList = decoded['favorites'] as List<dynamic>? ?? const <dynamic>[];
      for (final dynamic entry in favList) {
        try {
          final Gallery gallery = Gallery.fromJson(Map<String, dynamic>.from(entry as Map));
          if (seenGids.add(gallery.gid)) {
            parsedFavorites.add(gallery);
          }
        } catch (e) {
          log.error('Restore local favorite entry failed', e);
        }
      }

      final List<dynamic> colList = decoded['collections'] as List<dynamic>? ?? const <dynamic>[];
      for (final dynamic item in colList) {
        final String name = item.toString().trim();
        if (name.isNotEmpty && !parsedCollections.contains(name)) {
          parsedCollections.add(name);
        }
      }

      final dynamic rawMap = decoded['galleryCollections'];
      if (rawMap is Map) {
        rawMap.forEach((dynamic k, dynamic v) {
          final int? gid = int.tryParse(k.toString());
          if (gid == null || !seenGids.contains(gid) || v is! List) {
            return;
          }
          final List<String> cols = <String>[];
          for (final dynamic col in v) {
            final String name = col.toString().trim();
            if (name.isNotEmpty && !cols.contains(name)) {
              cols.add(name);
              if (!parsedCollections.contains(name)) {
                parsedCollections.add(name);
              }
            }
          }
          if (cols.isNotEmpty) {
            parsedAssignments[gid] = cols;
          }
        });
      }
    }

    _galleryCollections
      ..clear()
      ..addAll(parsedAssignments);
    collections.value = parsedCollections;
    favorites.value = parsedFavorites;
    revision.value++;
  }

  bool contains(int gid) {
    ensureRestored();
    return favorites.any((Gallery gallery) => gallery.gid == gid);
  }

  Gallery? find(int gid) {
    ensureRestored();
    for (final Gallery gallery in favorites) {
      if (gallery.gid == gid) {
        return gallery;
      }
    }
    return null;
  }

  /// Returns `true` when the gallery is favorited after this call.
  Future<bool> toggle(Gallery gallery) async {
    ensureRestored();
    final bool alreadyFavorited = contains(gallery.gid);

    if (alreadyFavorited) {
      await remove(gallery.gid);
    } else {
      await add(gallery);
    }

    return !alreadyFavorited;
  }

  Future<void> add(Gallery gallery, {Iterable<String>? initialCollections}) async {
    ensureRestored();

    /// Re-adding refreshes the stored snapshot (title, cover, page count).
    /// Replace the list in one assignment so observers are notified once, with
    /// the final list.
    final List<Gallery> next = List<Gallery>.of(favorites)
      ..removeWhere((Gallery e) => e.gid == gallery.gid)
      ..insert(0, gallery);

    if (initialCollections != null) {
      final List<String> normalized = _normalizeCollectionList(initialCollections);
      for (final String name in normalized) {
        if (!collections.contains(name)) {
          collections.add(name);
        }
      }
      if (normalized.isNotEmpty) {
        _galleryCollections[gallery.gid] = normalized;
      }
    }

    favorites.value = next;
    revision.value++;

    await _persist();
  }

  Future<void> remove(int gid) async {
    ensureRestored();
    if (!favorites.any((Gallery e) => e.gid == gid)) {
      return;
    }

    final List<Gallery> next = List<Gallery>.of(favorites)..removeWhere((Gallery e) => e.gid == gid);
    _galleryCollections.remove(gid);
    favorites.value = next;
    revision.value++;

    await _persist();
  }

  Future<void> clear() async {
    ensureRestored();
    _galleryCollections.clear();
    favorites.value = <Gallery>[];
    revision.value++;
    await _persist();
  }

  /// Returns the collection names assigned to [gid].
  List<String> collectionsOf(int gid) {
    ensureRestored();
    return List<String>.unmodifiable(_galleryCollections[gid] ?? const <String>[]);
  }

  /// Returns the number of local favorites assigned to [collectionName].
  int countInCollection(String collectionName) {
    ensureRestored();
    int total = 0;
    for (final Gallery g in favorites) {
      final List<String>? assigned = _galleryCollections[g.gid];
      if (assigned != null && assigned.contains(collectionName)) {
        total++;
      }
    }
    return total;
  }

  /// Returns favorites belonging to [collectionName], or all favorites when
  /// [collectionName] is `null` or empty.
  List<Gallery> favoritesInCollection(String? collectionName) {
    ensureRestored();
    if (collectionName == null || collectionName.trim().isEmpty) {
      return List<Gallery>.of(favorites);
    }
    return favorites.where((Gallery g) {
      final List<String>? assigned = _galleryCollections[g.gid];
      return assigned != null && assigned.contains(collectionName);
    }).toList();
  }

  /// Creates a new local collection if a non-empty unique name is given.
  /// Returns `true` if created.
  Future<bool> createCollection(String rawName) async {
    ensureRestored();
    final String name = rawName.trim();
    if (name.isEmpty) {
      return false;
    }
    final bool exists = collections.any((String c) => c.toLowerCase() == name.toLowerCase());
    if (exists) {
      return false;
    }

    collections.value = <String>[...collections, name];
    revision.value++;
    await _persist();
    return true;
  }

  /// Renames an existing collection and updates all gallery memberships.
  Future<bool> renameCollection(String oldName, String rawNewName) async {
    ensureRestored();
    final String newName = rawNewName.trim();
    if (newName.isEmpty || oldName == newName) {
      return false;
    }
    final int idx = collections.indexOf(oldName);
    if (idx < 0) {
      return false;
    }
    final bool conflict = collections.any(
      (String c) => c != oldName && c.toLowerCase() == newName.toLowerCase(),
    );
    if (conflict) {
      return false;
    }

    final List<String> nextCollections = List<String>.of(collections);
    nextCollections[idx] = newName;
    collections.value = nextCollections;

    for (final List<String> assigned in _galleryCollections.values) {
      final int pos = assigned.indexOf(oldName);
      if (pos >= 0) {
        assigned[pos] = newName;
      }
    }

    revision.value++;
    await _persist();
    return true;
  }

  /// Deletes a collection without deleting the galleries themselves.
  Future<bool> deleteCollection(String name) async {
    ensureRestored();
    if (!collections.contains(name)) {
      return false;
    }

    collections.value = List<String>.of(collections)..remove(name);
    final List<int> emptyKeys = <int>[];
    _galleryCollections.forEach((int gid, List<String> assigned) {
      assigned.remove(name);
      if (assigned.isEmpty) {
        emptyKeys.add(gid);
      }
    });
    for (final int gid in emptyKeys) {
      _galleryCollections.remove(gid);
    }

    revision.value++;
    await _persist();
    return true;
  }

  /// Replaces the collection assignments for a favorited gallery.
  Future<void> setGalleryCollections(int gid, Iterable<String> names) async {
    ensureRestored();
    if (!contains(gid)) {
      return;
    }

    final List<String> normalized = _normalizeCollectionList(names);
    bool addedCollection = false;
    final List<String> nextCollections = List<String>.of(collections);
    for (final String name in normalized) {
      if (!nextCollections.contains(name)) {
        nextCollections.add(name);
        addedCollection = true;
      }
    }
    if (addedCollection) {
      collections.value = nextCollections;
    }

    if (normalized.isEmpty) {
      _galleryCollections.remove(gid);
    } else {
      _galleryCollections[gid] = normalized;
    }

    revision.value++;
    await _persist();
  }

  /// Toggles membership of [gid] in [collectionName].
  Future<bool> toggleGalleryInCollection(int gid, String collectionName) async {
    ensureRestored();
    final List<String> current = List<String>.of(_galleryCollections[gid] ?? const <String>[]);
    final bool added;
    if (current.contains(collectionName)) {
      current.remove(collectionName);
      added = false;
    } else {
      current.add(collectionName);
      added = true;
    }
    await setGalleryCollections(gid, current);
    return added;
  }

  /// Exports a JSON-safe v2 snapshot including favorites and collections.
  Map<String, dynamic> exportPayload() {
    ensureRestored();
    return _buildPayload();
  }

  /// Imports a legacy array or v2 snapshot from backup.
  ///
  /// When [merge] is `true`, favorites are unioned by `gid` and collection
  /// memberships are unioned. When `false`, local favorites and collections
  /// are replaced. Returns the count of imported/merged favorites.
  Future<int> importPayload(dynamic raw, {bool merge = true}) async {
    ensureRestored();

    final List<Gallery> incomingFavorites = <Gallery>[];
    final Set<int> incomingGids = <int>{};
    final List<String> incomingCollections = <String>[];
    final Map<int, List<String>> incomingAssignments = <int, List<String>>{};

    if (raw is List) {
      for (final dynamic item in raw) {
        if (item is Map) {
          final Gallery g = Gallery.fromJson(Map<String, dynamic>.from(item));
          if (incomingGids.add(g.gid)) {
            incomingFavorites.add(g);
          }
        }
      }
    } else if (raw is Map) {
      final List<dynamic> favList = raw['favorites'] as List<dynamic>? ?? const <dynamic>[];
      for (final dynamic item in favList) {
        if (item is Map) {
          final Gallery g = Gallery.fromJson(Map<String, dynamic>.from(item));
          if (incomingGids.add(g.gid)) {
            incomingFavorites.add(g);
          }
        }
      }
      final List<dynamic> colList = raw['collections'] as List<dynamic>? ?? const <dynamic>[];
      for (final dynamic item in colList) {
        final String name = item.toString().trim();
        if (name.isNotEmpty && !incomingCollections.contains(name)) {
          incomingCollections.add(name);
        }
      }
      final dynamic rawMap = raw['galleryCollections'];
      if (rawMap is Map) {
        rawMap.forEach((dynamic k, dynamic v) {
          final int? gid = int.tryParse(k.toString());
          if (gid == null || !incomingGids.contains(gid) || v is! List) {
            return;
          }
          final List<String> cols = _normalizeCollectionList(v.map((e) => e.toString()));
          if (cols.isNotEmpty) {
            incomingAssignments[gid] = cols;
            for (final String col in cols) {
              if (!incomingCollections.contains(col)) {
                incomingCollections.add(col);
              }
            }
          }
        });
      }
    }

    if (!merge) {
      _galleryCollections
        ..clear()
        ..addAll(incomingAssignments);
      collections.value = incomingCollections;
      favorites.value = incomingFavorites;
      revision.value++;
      await _persist();
      return incomingFavorites.length;
    }

    final List<Gallery> nextFavorites = List<Gallery>.of(favorites);
    final Set<int> existingGids = nextFavorites.map((Gallery g) => g.gid).toSet();
    int added = 0;

    for (final Gallery g in incomingFavorites) {
      if (existingGids.add(g.gid)) {
        nextFavorites.add(g);
        added++;
      }
    }

    final List<String> nextCollections = List<String>.of(collections);
    bool changed = added > 0;

    for (final String col in incomingCollections) {
      if (!nextCollections.contains(col)) {
        nextCollections.add(col);
        changed = true;
      }
    }

    incomingAssignments.forEach((int gid, List<String> cols) {
      final List<String> existing = List<String>.of(_galleryCollections[gid] ?? const <String>[]);
      bool entryChanged = false;
      for (final String col in cols) {
        if (!existing.contains(col)) {
          existing.add(col);
          entryChanged = true;
        }
      }
      if (entryChanged) {
        _galleryCollections[gid] = existing;
        changed = true;
      }
    });

    if (changed) {
      collections.value = nextCollections;
      favorites.value = nextFavorites;
      revision.value++;
      await _persist();
    }

    return added;
  }

  List<String> _normalizeCollectionList(Iterable<String> names) {
    final List<String> result = <String>[];
    for (final String raw in names) {
      final String trimmed = raw.trim();
      if (trimmed.isNotEmpty && !result.contains(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  Map<String, dynamic> _buildPayload() {
    return <String, dynamic>{
      'version': _schemaVersion,
      'favorites': favorites.map((Gallery gallery) => gallery.toJson()).toList(),
      'collections': collections.toList(),
      'galleryCollections': <String, List<String>>{
        for (final MapEntry<int, List<String>> e in _galleryCollections.entries)
          e.key.toString(): List<String>.of(e.value),
      },
    };
  }

  Future<void> _persist() {
    return _store.writeJson(_buildPayload());
  }
}
