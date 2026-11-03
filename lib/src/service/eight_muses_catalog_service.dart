import 'dart:convert';

import 'package:acervo_hc/src/model/eight_muses_search.dart';
import 'package:acervo_hc/src/network/eight_muses_request.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/storage_service.dart';

EightMusesCatalogService eightMusesCatalogService = EightMusesCatalogService();

/// Caches the site's tag/artist directories and the page's recent searches.
///
/// Everything lives in [storageService] (GetStorage) instead of the
/// local_config table so no new [ConfigEnum] value (and no cloud-sync surface)
/// is needed.
class EightMusesCatalogService {
  static const String _tagsKey = 'eightMusesTags';
  static const String _tagsFetchedAtKey = 'eightMusesTagsFetchedAt';
  static const String _artistsKey = 'eightMusesArtists';
  static const String _artistsFetchedAtKey = 'eightMusesArtistsFetchedAt';
  static const String _recentSearchesKey = 'eightMusesRecentSearches';
  static const int _maxRecentSearches = 20;
  static const Duration _maxAge = Duration(days: 7);

  final _Directory _tags = _Directory();
  final _Directory _artists = _Directory();

  bool _restored = false;

  List<EightMusesTag> get tags => _tags.items;

  List<EightMusesTag> get artists => _artists.items;

  bool get loadingTags => _tags.loading;

  bool get loadingArtists => _artists.loading;

  String? get tagsError => _tags.error;

  String? get artistsError => _artists.error;

  Future<void> ensureTags({bool force = false}) {
    _restore();
    return _ensure(
      directory: _tags,
      fetch: eightMusesRequest.requestTags,
      itemsKey: _tagsKey,
      fetchedAtKey: _tagsFetchedAtKey,
      force: force,
    );
  }

  Future<void> ensureArtists({bool force = false}) {
    _restore();
    return _ensure(
      directory: _artists,
      fetch: eightMusesRequest.requestArtists,
      itemsKey: _artistsKey,
      fetchedAtKey: _artistsFetchedAtKey,
      force: force,
    );
  }

  Future<void> _ensure({
    required _Directory directory,
    required Future<List<EightMusesTag>> Function() fetch,
    required String itemsKey,
    required String fetchedAtKey,
    required bool force,
  }) async {
    if (directory.loading) {
      return;
    }

    final bool isFresh = directory.fetchedAt != null && DateTime.now().difference(directory.fetchedAt!) < _maxAge;
    if (!force && directory.items.isNotEmpty && isFresh) {
      return;
    }

    directory.loading = true;
    directory.error = null;
    try {
      final List<EightMusesTag> fetched = await fetch();
      if (fetched.isNotEmpty) {
        directory.items
          ..clear()
          ..addAll(fetched);
        directory.fetchedAt = DateTime.now();
        _persistItems(itemsKey, fetchedAtKey, directory);
      }
    } catch (e, s) {
      directory.error = e.toString();
      log.error('Load 8muses directory failed ($itemsKey)', e, s);
    } finally {
      directory.loading = false;
    }
  }

  List<String> readRecentSearches() {
    _restore();
    final String? raw = storageService.read<String>(_recentSearchesKey);
    if (raw == null || raw.isEmpty) {
      return <String>[];
    }

    try {
      return (jsonDecode(raw) as List).map((dynamic e) => e.toString()).toList();
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> addRecentSearch(String keyword) async {
    final String normalized = keyword.trim();
    if (normalized.isEmpty) {
      return;
    }

    final List<String> recent = readRecentSearches()..removeWhere((String e) => e.toLowerCase() == normalized.toLowerCase());
    recent.insert(0, normalized);
    if (recent.length > _maxRecentSearches) {
      recent.removeRange(_maxRecentSearches, recent.length);
    }

    await storageService.write(_recentSearchesKey, jsonEncode(recent));
  }

  Future<void> clearRecentSearches() => storageService.write(_recentSearchesKey, jsonEncode(<String>[]));

  Future<void> removeRecentSearch(String keyword) async {
    final String normalized = keyword.trim();
    if (normalized.isEmpty) {
      return;
    }

    final List<String> recent = readRecentSearches()..removeWhere((String e) => e.toLowerCase() == normalized.toLowerCase());
    await storageService.write(_recentSearchesKey, jsonEncode(recent));
  }

  void _restore() {
    if (_restored) {
      return;
    }
    _restored = true;

    _restoreItems(_tags, _tagsKey, _tagsFetchedAtKey);
    _restoreItems(_artists, _artistsKey, _artistsFetchedAtKey);
  }

  void _restoreItems(_Directory directory, String itemsKey, String fetchedAtKey) {
    try {
      final String? raw = storageService.read<String>(itemsKey);
      if (raw != null && raw.isNotEmpty && directory.items.isEmpty) {
        final List<dynamic> decoded = jsonDecode(raw) as List;
        directory.items.addAll(
          decoded.map(
            (dynamic e) => EightMusesTag(
              slug: e['slug'].toString(),
              label: e['label'].toString(),
              count: int.tryParse(e['count'].toString()) ?? 0,
            ),
          ),
        );
      }

      final int? fetchedAtMillis = storageService.read<int>(fetchedAtKey);
      if (fetchedAtMillis != null) {
        directory.fetchedAt = DateTime.fromMillisecondsSinceEpoch(fetchedAtMillis);
      }
    } catch (e) {
      log.error('Restore 8muses directory failed ($itemsKey)', e);
    }
  }

  void _persistItems(String itemsKey, String fetchedAtKey, _Directory directory) {
    storageService.write(
      itemsKey,
      jsonEncode(directory.items.map((EightMusesTag item) => <String, dynamic>{'slug': item.slug, 'label': item.label, 'count': item.count}).toList()),
    );
    storageService.write(fetchedAtKey, DateTime.now().millisecondsSinceEpoch);
  }
}

class _Directory {
  final List<EightMusesTag> items = <EightMusesTag>[];
  bool loading = false;
  String? error;
  DateTime? fetchedAt;
}
