import 'package:dio/dio.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/model/xlecx_detail.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/setting/network_setting.dart';
import 'package:acervo_hc/src/service/xlecx_session_service.dart';
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

  /// Markers carried by the [DioException.error] of a page the site refuses to
  /// serve, so the UI can show a source-specific message instead of the raw
  /// status code.
  static const String restrictedErrorMarker = 'xlecxRestricted';
  static const String notFoundErrorMarker = 'xlecxNotFound';
  static const String cloudflareErrorMarker = 'xlecxCloudflare';

  static String? errorMarkerOf(Object error) {
    if (error is! DioException) {
      return null;
    }
    final dynamic value = error.error;
    return value is String ? value : null;
  }

  /// Non-5xx statuses are accepted so the body can be inspected: the site
  /// answers 403 both for its Cloudflare challenge and for posts that only
  /// registered users may see, and the message tells them apart.
  static Options get _htmlOptions => Options(
        responseType: ResponseType.plain,
        validateStatus: (int? status) => status != null && status < 500,
      );

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
    )..interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
            /// The user's session (when configured) unlocks the posts the site
            /// restricts to registered users. Read on every request so saving
            /// or clearing the cookie takes effect immediately.
            final String? cookie = xlecxSessionService.cookie;
            if (cookie != null) {
              options.headers['Cookie'] = cookie;
            }
            handler.next(options);
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
            options: _htmlOptions,
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
              validateStatus: (int? status) => status != null && status < 500,
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
      options: _htmlOptions,
    );

    return XlecxParser.parseTags(_checkedHtml(response));
  }

  /// True when the configured cookies are accepted by the site, false when it
  /// still treats the client as a guest, null when the check itself failed
  /// (network, Cloudflare).
  ///
  /// The logged-in header carries `header__login-btn--logged`; the guest one
  /// only has the plain `js-show-login` button. Checking the header avoids
  /// depending on any specific post.
  Future<bool?> verifySession() async {
    if (!xlecxSessionService.hasCookie) {
      return false;
    }

    try {
      final Response<String> response = await dio.get<String>('$baseUrl/', options: _htmlOptions);
      final String html = _checkedHtml(response);

      if (html.contains('header__login-btn--logged')) {
        return true;
      }
      if (html.contains('js-show-login')) {
        return false;
      }
      return null;
    } on DioException {
      return null;
    }
  }

  Future<XlecxDetail> requestDetail(GalleryUrl galleryUrl) async {
    final Response<String> response = await dio.get<String>(
      galleryUrl.url,
      options: _htmlOptions,
    );

    final int id = galleryUrl.externalId!;
    final XlecxDetail? detail = XlecxParser.parseDetail(_checkedHtml(response), id);
    if (detail == null) {
      /// No page images: a video post or a post whose gallery was pulled.
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: notFoundErrorMarker,
        message: 'Xlecx post #$id has no page images',
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
      options: _htmlOptions,
    );

    final String html = _checkedHtml(response);
    return XlecxPage(
      galleries: XlecxParser.parseGalleryList(html),
      hasMore: XlecxParser.parseHasNextPage(html),
    );
  }

  /// Turns a refused page into a marker the UI (and the download engine) can
  /// translate.
  ///
  /// The site is behind Cloudflare, but only as a proxy: a browser User-Agent
  /// gets the HTML without a challenge. Two other answers are expected and are
  /// not transient:
  ///
  /// - `403` + "Guests do not have the required permissions": the post is
  ///   restricted to registered users (some listings still show it);
  /// - `404`: the post was removed.
  static String _checkedHtml(Response<String> response) {
    final String html = response.data ?? '';
    final int? status = response.statusCode;

    if (html.contains('Just a moment') || html.contains('_cf_chl_opt')) {
      throw _refused(response, cloudflareErrorMarker, 'Xlecx is behind a Cloudflare challenge');
    }

    if (html.contains('do not have the required permissions')) {
      throw _refused(response, restrictedErrorMarker, 'Xlecx post is restricted to registered users');
    }

    if (status != null && status >= 400) {
      throw _refused(response, notFoundErrorMarker, 'Xlecx answered $status');
    }

    return html;
  }

  static DioException _refused(Response<String> response, String marker, String message) {
    return DioException(
      requestOptions: response.requestOptions,
      response: response,
      type: DioExceptionType.badResponse,
      error: marker,
      message: message,
    );
  }
}

final XlecxRequest xlecxRequest = XlecxRequest();
