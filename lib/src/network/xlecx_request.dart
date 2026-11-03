import 'package:dio/dio.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/model/xlecx_detail.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/setting/network_setting.dart';
import 'package:acervo_hc/src/utils/xlecx_parser.dart';

/// One page of a Xlecx listing.
///
/// The site clamps out-of-range pages instead of answering 404 (asking for page
/// 9999 returns the last page), so [hasMore] comes from the "Next" link of the
/// pagination block, not from the card count.
class XlecxPage {
  final List<Gallery> galleries;
  final bool hasMore;

  const XlecxPage({required this.galleries, required this.hasMore});
}

/// HTTP client for https://xlecx.one.
///
/// Deliberately separate from the E-H request layer: no E-H cookies, no domain
/// fronting and no E-H cache. Cloudflare sits in front of the site only as a
/// proxy — it serves the HTML to any client that sends a browser User-Agent, so
/// a plain Dio instance is enough (no clearance, no curl).
class XlecxRequest {
  static const String baseUrl = XlecxParser.baseUrl;

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36';

  static const String _accept =
      'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8';

  Dio? _dio;

  /// Page lists resolved from a post, reused by the reader and by the download
  /// engine. Keyed by gallery gid.
  final Map<int, List<String>> _pageUrls = <int, List<String>>{};
  final Map<int, Future<List<String>>> _pageUrlsInFlight = <int, Future<List<String>>>{};

  Dio get dio => _dio ??= _createDio();

  Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: Duration(milliseconds: networkSetting.connectTimeout.value),
        receiveTimeout: Duration(milliseconds: networkSetting.receiveTimeout.value),
        headers: <String, dynamic>{
          'User-Agent': _userAgent,
          'Accept': _accept,
          'Accept-Language': 'en-US,en;q=0.9',
          'Sec-Fetch-Dest': 'document',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Site': 'none',
          'Upgrade-Insecure-Requests': '1',
        },
      ),
    );
  }

  /// A `/f/` listing: category, tags, artist/parody and sort. The site applies
  /// every filter server side, so nothing is filtered locally.
  Future<XlecxPage> requestFiltered({required XlecxSearchConfig config, required int page}) {
    final String path = XlecxParser.filterPath(
      category: config.category,
      includeTags: config.includeTags.map((XlecxTag tag) => tag.slug).toList(),
      excludeTags: config.excludeTags.map((XlecxTag tag) => tag.slug).toList(),
      artist: config.artist?.slug,
      parody: config.parody?.slug,
      group: config.group?.slug,
      sort: config.sort,
      page: page,
    );

    return _requestGalleryPage(path);
  }

  /// Keyword search. The site only paginates its search through a POSTed
  /// `search_start`, and a search ignores the `/f/` filters (site behaviour).
  Future<XlecxPage> search({required XlecxSearchConfig config, required int page}) async {
    final String keyword = config.keyword.trim();

    final Response<String> response = page <= 1
        ? await dio.get<String>(
            '$baseUrl/index.php',
            queryParameters: <String, dynamic>{
              'do': 'search',
              'subaction': 'search',
              'story': keyword,
            },
            options: Options(responseType: ResponseType.plain),
          )
        : await dio.post<String>(
            '$baseUrl/index.php',
            data: <String, dynamic>{
              'do': 'search',
              'subaction': 'search',
              'story': keyword,
              'search_start': page,
            },
            options: Options(
              responseType: ResponseType.plain,
              contentType: Headers.formUrlEncodedContentType,
            ),
          );

    final String html = _checkedHtml(response);
    return XlecxPage(
      galleries: XlecxParser.parseGalleryList(html),
      hasMore: XlecxParser.parseHasNextPage(html),
    );
  }

  /// The `/tags/` directory (one page, ~1000 tags).
  Future<List<XlecxTag>> requestTags() async {
    final Response<String> response = await dio.get<String>(
      '$baseUrl/tags/',
      options: Options(responseType: ResponseType.plain),
    );

    return XlecxParser.parseTags(_checkedHtml(response));
  }

  Future<XlecxDetail> requestDetail(GalleryUrl galleryUrl) async {
    final Response<String> response = await dio.get<String>(
      galleryUrl.url,
      options: Options(responseType: ResponseType.plain),
    );

    final int id = galleryUrl.externalId!;
    final XlecxDetail? detail = XlecxParser.parseDetail(_checkedHtml(response), id);
    if (detail == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        error: 'Unable to parse Xlecx gallery #$id',
        type: DioExceptionType.badResponse,
        response: response,
      );
    }

    _pageUrls[galleryUrl.gid] = detail.pageUrls;
    return detail;
  }

  /// Resolves (and caches) the full size page urls of a gallery. Used by the
  /// download engine, which only has the gallery url when it starts a task.
  Future<List<String>> requestPageUrls(GalleryUrl galleryUrl) {
    final List<String>? cached = _pageUrls[galleryUrl.gid];
    if (cached != null) {
      return Future<List<String>>.value(cached);
    }

    return _pageUrlsInFlight[galleryUrl.gid] ??= requestDetail(galleryUrl)
        .then((XlecxDetail detail) => detail.pageUrls)
        .whenComplete(() {
      _pageUrlsInFlight.remove(galleryUrl.gid);
    });
  }

  Future<Response> download({
    required String url,
    required String path,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    int? receiveTimeout,
  }) {
    return dio.download(
      url,
      path,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      deleteOnError: true,
      options: Options(receiveTimeout: Duration(milliseconds: receiveTimeout ?? 0)),
    );
  }

  Future<XlecxPage> _requestGalleryPage(String path) async {
    final Response<String> response = await dio.get<String>(
      '$baseUrl$path',
      options: Options(responseType: ResponseType.plain),
    );

    final String html = _checkedHtml(response);
    return XlecxPage(
      galleries: XlecxParser.parseGalleryList(html),
      hasMore: XlecxParser.parseHasNextPage(html),
    );
  }

  /// The site is behind Cloudflare, but only as a proxy: a browser User-Agent
  /// gets the page without a challenge. If that ever changes, fail with a clear
  /// message instead of parsing the challenge document as an empty listing.
  static String _checkedHtml(Response<String> response) {
    final String html = response.data ?? '';
    if (response.statusCode == 403 || html.contains('Just a moment') || html.contains('_cf_chl_opt')) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Xlecx is behind a Cloudflare challenge, try again later',
      );
    }
    return html;
  }
}

final XlecxRequest xlecxRequest = XlecxRequest();
