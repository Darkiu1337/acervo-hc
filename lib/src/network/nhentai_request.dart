import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/model/nhentai_gallery.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/setting/network_setting.dart';

/// HTTP client for nhentai API v2 (`https://nhentai.net/api/v2/`).
///
/// Separate from the E-Hentai request layer: no E-H cookies, no domain
/// fronting, and pure JSON endpoints that work directly without an API key.
class NHentaiRequest {
  static const String baseUrl = 'https://nhentai.net';
  static const String apiBaseUrl = 'https://nhentai.net/api/v2';

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

  Dio? _dio;
  NHentaiCdnConfig? _cdn;
  Future<NHentaiCdnConfig>? _cdnInFlight;

  /// Resolved full-size page URLs cached by Acervo H&C gid for the download
  /// engine.
  final Map<int, List<String>> _pageUrls = <int, List<String>>{};
  final Map<int, Future<List<String>>> _pageUrlsInFlight = <int, Future<List<String>>>{};

  Dio get dio => _dio ??= _createDio();

  Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: Duration(milliseconds: networkSetting.connectTimeout.value),
        receiveTimeout: Duration(milliseconds: networkSetting.receiveTimeout.value),
        headers: const <String, dynamic>{
          'User-Agent': _userAgent,
          'Accept': 'application/json',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ),
    );
  }

  /// Fetches and caches CDN hosts from `/api/v2/cdn`, falling back to known
  /// defaults if the CDN endpoint is temporarily unavailable.
  Future<NHentaiCdnConfig> ensureCdn() {
    if (_cdn != null) {
      return Future<NHentaiCdnConfig>.value(_cdn!);
    }
    return _cdnInFlight ??= _loadCdn();
  }

  Future<NHentaiCdnConfig> _loadCdn() async {
    try {
      final Map<String, dynamic> data = await _getJson('$apiBaseUrl/cdn');
      final NHentaiCdnConfig config = NHentaiCdnConfig.fromJson(data);
      _cdn = config;
      return config;
    } catch (e) {
      log.warning('Failed to load nhentai CDN config, using fallback hosts: $e');
      _cdnInFlight = null;
      return NHentaiCdnConfig.fallback;
    }
  }

  /// Combines optional user search text and quick language filter into an
  /// nhentai API v2 search query.
  static String buildEffectiveQuery({
    required String query,
    required NHentaiLanguage language,
    required NHentaiSort sort,
  }) {
    final List<String> parts = <String>[];
    final String trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      parts.add(trimmed);
    }
    if (language.queryClause.isNotEmpty && !trimmed.toLowerCase().contains(language.queryClause)) {
      parts.add(language.queryClause);
    }
    if (parts.isEmpty) {
      return sort == NHentaiSort.recent ? '' : '*';
    }
    return parts.join(' ');
  }

  /// Requests one page of galleries (recent feed or sorted search).
  Future<NHentaiSearchPage> requestGalleries({
    required int page,
    required NHentaiSort sort,
    required NHentaiLanguage language,
    String query = '',
  }) async {
    final NHentaiCdnConfig cdn = await ensureCdn();
    final String effectiveQuery = buildEffectiveQuery(query: query, language: language, sort: sort);

    final Map<String, dynamic> data;
    if (effectiveQuery.isEmpty && sort == NHentaiSort.recent) {
      data = await _getJson(
        '$apiBaseUrl/galleries',
        queryParameters: <String, dynamic>{'page': page},
      );
    } else {
      data = await _getJson(
        '$apiBaseUrl/search',
        queryParameters: <String, dynamic>{
          'query': effectiveQuery.isEmpty ? '*' : effectiveQuery,
          'sort': sort.apiValue,
          'page': page,
        },
      );
    }

    final List<NHentaiGallerySummary> items = (data['result'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map raw) => NHentaiGallerySummary.fromJson(Map<String, dynamic>.from(raw), cdn))
        .toList();

    return NHentaiSearchPage(
      items: items,
      currentPage: page,
      totalPages: (data['num_pages'] as num?)?.toInt() ?? page,
      totalCount: (data['total'] as num?)?.toInt() ?? items.length,
    );
  }

  /// Requests full metadata and page image URLs for one gallery.
  Future<NHentaiGalleryDetail> requestDetail(int id) async {
    final NHentaiCdnConfig cdn = await ensureCdn();
    final Map<String, dynamic> data = await _getJson('$apiBaseUrl/galleries/$id');
    final NHentaiGalleryDetail detail = NHentaiGalleryDetail.fromJson(data, cdn);
    if (detail.pageUrls.isNotEmpty) {
      _pageUrls[detail.galleryUrl.gid] = detail.pageUrls;
    }
    return detail;
  }

  /// Requests related galleries for a given gallery id.
  Future<List<NHentaiGallerySummary>> requestRelated(int id) async {
    final NHentaiCdnConfig cdn = await ensureCdn();
    final Map<String, dynamic> data = await _getJson('$apiBaseUrl/galleries/$id/related');
    return (data['result'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map raw) => NHentaiGallerySummary.fromJson(Map<String, dynamic>.from(raw), cdn))
        .toList();
  }

  /// Resolves and caches full page URLs for the download task runner.
  Future<List<String>> requestPageUrls(GalleryUrl galleryUrl) {
    final List<String>? cached = _pageUrls[galleryUrl.gid];
    if (cached != null) {
      return Future<List<String>>.value(cached);
    }
    return _pageUrlsInFlight[galleryUrl.gid] ??= _fetchPageUrls(galleryUrl);
  }

  Future<List<String>> _fetchPageUrls(GalleryUrl galleryUrl) async {
    try {
      final int id = galleryUrl.externalId!;
      final NHentaiGalleryDetail detail = await requestDetail(id);
      return detail.pageUrls;
    } finally {
      _pageUrlsInFlight.remove(galleryUrl.gid);
    }
  }

  /// Downloads one image file to [path] for the gallery download engine.
  Future<Response<dynamic>> download({
    required String url,
    required String path,
    int? receiveTimeout,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return dio.download(
      url,
      path,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      options: Options(
        receiveTimeout: receiveTimeout == null ? null : Duration(milliseconds: receiveTimeout),
        headers: const <String, dynamic>{
          'Referer': '$baseUrl/',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String url, {
    Map<String, dynamic>? queryParameters,
  }) async {
    DioException? lastRateLimit;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final Response<dynamic> response = await dio.get<dynamic>(
          url,
          queryParameters: queryParameters,
          options: Options(responseType: ResponseType.plain),
        );
        final dynamic decoded = response.data is String ? jsonDecode(response.data as String) : response.data;
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        throw FormatException('Unexpected nhentai API response shape for $url');
      } on DioException catch (e) {
        if (e.response?.statusCode == 429 && attempt == 0) {
          lastRateLimit = e;
          await Future<void>.delayed(const Duration(milliseconds: 900));
          continue;
        }
        rethrow;
      }
    }
    throw lastRateLimit!;
  }
}

final NHentaiRequest nhentaiRequest = NHentaiRequest();
