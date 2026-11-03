import 'dart:convert';

import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/network/xlecx_request.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/storage_service.dart';

XlecxCatalogService xlecxCatalogService = XlecxCatalogService();

/// Caches the site's tag directory and the page's recent searches.
///
/// Everything lives in [storageService] (GetStorage) instead of the
/// local_config table so no new [ConfigEnum] value (and no cloud-sync surface)
/// is needed.
class XlecxCatalogService {
  static const String _tagsKey = 'xlecxTags';
  static const String _tagsFetchedAtKey = 'xlecxTagsFetchedAt';
  static const String _recentSearchesKey = 'xlecxRecentSearches';
  static const int _maxRecentSearches = 20;
  static const Duration _maxAge = Duration(days: 7);

  final List<XlecxTag> _tags = <XlecxTag>[];

  bool loadingTags = false;
  String? tagsError;

  bool _restored = false;
  DateTime? _tagsFetchedAt;

  List<XlecxTag> get tags => _tags;

  /// Loads `/tags/` once (cached for [_maxAge]).
  Future<void> ensureTags({bool force = false}) async {
    if (loadingTags) {
      return;
    }

    _restore();

    final bool isFresh = _tagsFetchedAt != null && DateTime.now().difference(_tagsFetchedAt!) < _maxAge;
    if (!force && _tags.isNotEmpty && isFresh) {
      return;
    }

    loadingTags = true;
    tagsError = null;
    try {
      final List<XlecxTag> fetched = await xlecxRequest.requestTags();
      if (fetched.isNotEmpty) {
        _tags
          ..clear()
          ..addAll(fetched);
        _tagsFetchedAt = DateTime.now();
        _persist();
      }
    } catch (e, s) {
      tagsError = e.toString();
      log.error('Load Xlecx tags failed', e, s);
    } finally {
      loadingTags = false;
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

    try {
      final String? raw = storageService.read<String>(_tagsKey);
      if (raw != null && raw.isNotEmpty && _tags.isEmpty) {
        final List<dynamic> decoded = jsonDecode(raw) as List;
        _tags.addAll(
          decoded.map(
            (dynamic e) => XlecxTag(
              slug: e['slug'].toString(),
              label: e['label'].toString(),
              count: int.tryParse(e['count'].toString()) ?? 0,
            ),
          ),
        );
      }

      final int? fetchedAtMillis = storageService.read<int>(_tagsFetchedAtKey);
      if (fetchedAtMillis != null) {
        _tagsFetchedAt = DateTime.fromMillisecondsSinceEpoch(fetchedAtMillis);
      }
    } catch (e) {
      log.error('Restore Xlecx tags failed', e);
    }
  }

  void _persist() {
    storageService.write(
      _tagsKey,
      jsonEncode(_tags.map((XlecxTag tag) => <String, dynamic>{'slug': tag.slug, 'label': tag.label, 'count': tag.count}).toList()),
    );
    storageService.write(_tagsFetchedAtKey, DateTime.now().millisecondsSinceEpoch);
  }
}
