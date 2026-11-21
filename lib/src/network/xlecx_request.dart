import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/model/xlecx_detail.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/service/isolate_service.dart';
import 'package:acervo_hc/src/service/xlecx_session_service.dart';
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

/// Outcome of a credential-based Xlecx login attempt.
class XlecxLoginResult {
  final bool success;
  final String? username;
  final String? errorMessage;
  final bool isCloudflareBlocked;

  const XlecxLoginResult({
    required this.success,
    this.username,
    this.errorMessage,
    this.isCloudflareBlocked = false,
  });
}

XlecxPage _parseGalleryPageInIsolate(String html) {
  return XlecxPage(
    galleries: XlecxParser.parseGalleryList(html),
    hasMore: XlecxParser.parseHasNextPage(html),
  );
}

XlecxDetail? _parseDetailInIsolate(List<dynamic> args) {
  return XlecxParser.parseDetail(args[0] as String, args[1] as int);
}

List<XlecxTag> _parseTagsInIsolate(String html) {
  return XlecxParser.parseTags(html);
}

/// HTTP client for https://xlecx.one.
///
/// Deliberately separate from the E-H request layer: no E-H cookies, no domain
/// fronting and no E-H cache. Cloudflare sits in front of the site only as a
/// proxy — it serves the HTML to any client that sends a browser User-Agent, so
/// a plain Dio instance is enough (no clearance, no curl).
class XlecxRequest {
  static const String baseUrl = XlecxParser.baseUrl;

  static const String _skipCookieExtraKey = 'skipXlecxCookie';

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
  ///
  /// Redirects are followed by hand because the site sends raw non-ASCII bytes
  /// in `Location` (post slugs carry `’`, as in
  /// `/64748-my-son’s-hyperspermia-2.html`), which Dio cannot resolve and
  /// reports as a redirect loop.
  static Options get _htmlOptions => Options(
        responseType: ResponseType.plain,
        validateStatus: (int? status) => status != null && status < 500,
        followRedirects: false,
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
            if (options.extra[_skipCookieExtraKey] == true) {
              handler.next(options);
              return;
            }

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

  /// Signs into Xlecx directly using DataLife Engine's login form
  /// (`login_name`, `login_password`, `login=submit`).
  ///
  /// Omitting `login_not_save` enables DLE's "remember me" so the response sets
  /// `PHPSESSID` together with persistent `dle_user_id` + `dle_password`
  /// cookies — the plaintext password is never persisted on disk.
  Future<XlecxLoginResult> login({
    required String username,
    required String password,
  }) async {
    final String trimmedUser = username.trim();
    if (trimmedUser.isEmpty || password.isEmpty) {
      return const XlecxLoginResult(success: false);
    }

    final Map<String, String> collectedCookies = <String, String>{};

    try {
      Response<String> response = await dio.post<String>(
        '$baseUrl/',
        data: <String, dynamic>{
          'login_name': trimmedUser,
          'login_password': password,
          'login': 'submit',
        },
        options: Options(
          responseType: ResponseType.plain,
          contentType: 'application/x-www-form-urlencoded',
          validateStatus: (int? status) => status != null && status < 500,
          followRedirects: false,
          headers: <String, dynamic>{
            'Origin': baseUrl,
            'Referer': '$baseUrl/',
            'Sec-Fetch-Site': 'same-origin',
          },
          extra: const <String, dynamic>{_skipCookieExtraKey: true},
        ),
      );

      _mergeSetCookies(response, collectedCookies);

      /// Follow up to 4 redirects manually while carrying the newly issued
      /// session cookies.
      String currentUrl = '$baseUrl/';
      int hops = 0;
      while (response.statusCode != null &&
          response.statusCode! >= 300 &&
          response.statusCode! < 400 &&
          hops < 4) {
        final String? location = response.headers.value('location');
        if (location == null || location.isEmpty) {
          break;
        }
        final String nextUrl = _resolveUrl(currentUrl, location);
        if (nextUrl == currentUrl) {
          break;
        }
        currentUrl = nextUrl;
        hops++;

        final String cookieHeader = _formatCookieHeader(collectedCookies);
        response = await dio.get<String>(
          currentUrl,
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (int? status) => status != null && status < 500,
            followRedirects: false,
            headers: <String, dynamic>{
              if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
              'Referer': '$baseUrl/',
              'Sec-Fetch-Site': 'same-origin',
            },
            extra: const <String, dynamic>{_skipCookieExtraKey: true},
          ),
        );
        _mergeSetCookies(response, collectedCookies);
      }

      String html = response.data ?? '';
      if (_isCloudflareHtml(html)) {
        return const XlecxLoginResult(success: false, isCloudflareBlocked: true);
      }

      final String? phpsessid = _cookieValueIgnoreCase(collectedCookies, XlecxSessionService.phpsessidCookieName);
      final String? dleUserId = _cookieValueIgnoreCase(collectedCookies, XlecxSessionService.userIdCookieName);
      final String? dlePassword = _cookieValueIgnoreCase(collectedCookies, XlecxSessionService.passwordCookieName);

      bool loggedIn = XlecxParser.isLoggedInHtml(html);

      /// Some DLE setups set auth cookies on the POST and render the logged-in
      /// header on the next GET. Verify once if we received auth cookies without
      /// an explicit error message.
      final String? errorBanner = XlecxParser.parseLoginError(html);
      if (!loggedIn &&
          errorBanner == null &&
          ((dleUserId != null && dlePassword != null) || phpsessid != null)) {
        final String cookieHeader = _formatCookieHeader(collectedCookies);
        if (cookieHeader.isNotEmpty) {
          final Response<String> verifyResponse = await dio.get<String>(
            '$baseUrl/',
            options: Options(
              responseType: ResponseType.plain,
              validateStatus: (int? status) => status != null && status < 500,
              followRedirects: false,
              headers: <String, dynamic>{'Cookie': cookieHeader},
              extra: const <String, dynamic>{_skipCookieExtraKey: true},
            ),
          );
          _mergeSetCookies(verifyResponse, collectedCookies);
          final String verifyHtml = verifyResponse.data ?? '';
          if (_isCloudflareHtml(verifyHtml)) {
            return const XlecxLoginResult(success: false, isCloudflareBlocked: true);
          }
          if (XlecxParser.isLoggedInHtml(verifyHtml)) {
            html = verifyHtml;
            loggedIn = true;
          }
        }
      }

      if (!loggedIn) {
        return XlecxLoginResult(
          success: false,
          errorMessage: errorBanner,
        );
      }

      final String finalPhpsessid = _cookieValueIgnoreCase(collectedCookies, XlecxSessionService.phpsessidCookieName) ?? '';
      final String finalUserId = _cookieValueIgnoreCase(collectedCookies, XlecxSessionService.userIdCookieName) ?? '';
      final String finalPassword = _cookieValueIgnoreCase(collectedCookies, XlecxSessionService.passwordCookieName) ?? '';

      if (finalPhpsessid.isEmpty && finalUserId.isEmpty && finalPassword.isEmpty) {
        return const XlecxLoginResult(success: false);
      }

      final String displayUsername = XlecxParser.parseLoggedInUsername(html) ?? trimmedUser;
      await xlecxSessionService.save(
        phpsessid: finalPhpsessid,
        dleUserId: finalUserId,
        dlePassword: finalPassword,
        username: displayUsername,
      );

      return XlecxLoginResult(success: true, username: displayUsername);
    } on DioException catch (e) {
      return XlecxLoginResult(
        success: false,
        errorMessage: e.message,
        isCloudflareBlocked: errorMarkerOf(e) == cloudflareErrorMarker,
      );
    } catch (e) {
      return XlecxLoginResult(success: false, errorMessage: e.toString());
    }
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
        ? await _get(
            '$baseUrl/index.php',
            queryParameters: <String, dynamic>{
              'do': 'search',
              'subaction': 'search',
              'story': keyword,
            },
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
              contentType: 'application/x-www-form-urlencoded',
              validateStatus: (int? status) => status != null && status < 500,
            ),
          );

    final String html = _checkedHtml(response);
    return _parseGalleryPage(html);
  }

  /// The `/tags/` directory (one page, ~1000 tags).
  Future<List<XlecxTag>> requestTags() async {
    final Response<String> response = await _get('$baseUrl/tags/');
    final String html = _checkedHtml(response);

    if (isolateService.isInitialized) {
      return isolateService.run(_parseTagsInIsolate, html);
    }
    return _parseTagsInIsolate(html);
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
      final Response<String> response = await _get('$baseUrl/');
      final String html = _checkedHtml(response);

      if (XlecxParser.isLoggedInHtml(html)) {
        final String? parsedUser = XlecxParser.parseLoggedInUsername(html);
        if (parsedUser != null && parsedUser != xlecxSessionService.username) {
          await xlecxSessionService.save(
            phpsessid: xlecxSessionService.phpsessid ?? '',
            dleUserId: xlecxSessionService.dleUserId ?? '',
            dlePassword: xlecxSessionService.dlePassword ?? '',
            username: parsedUser,
          );
        }
        return true;
      }
      if (XlecxParser.isGuestHtml(html)) {
        return false;
      }
      return null;
    } on DioException {
      return null;
    }
  }

  Future<XlecxDetail> requestDetail(GalleryUrl galleryUrl) async {
    final Response<String> response = await _get(galleryUrl.url);

    final int id = galleryUrl.externalId!;
    final String html = _checkedHtml(response);
    final XlecxDetail? detail = isolateService.isInitialized
        ? await isolateService.run(_parseDetailInIsolate, <dynamic>[html, id])
        : _parseDetailInIsolate(<dynamic>[html, id]);

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
    final Response<String> response = await _get('$baseUrl$path');
    final String html = _checkedHtml(response);
    return _parseGalleryPage(html);
  }

  Future<XlecxPage> _parseGalleryPage(String html) {
    if (isolateService.isInitialized) {
      return isolateService.run(_parseGalleryPageInIsolate, html);
    }
    return Future<XlecxPage>.value(_parseGalleryPageInIsolate(html));
  }

  /// GET with manual redirect handling (see [_htmlOptions]).
  Future<Response<String>> _get(String url, {Map<String, dynamic>? queryParameters, int hop = 0}) async {
    final Response<String> response = await dio.get<String>(
      url,
      queryParameters: queryParameters,
      options: _htmlOptions,
    );

    final int? status = response.statusCode;
    final String? location = response.headers.value('location');
    if (status != null && status >= 300 && status < 400 && location != null && location.isNotEmpty) {
      final String next = _resolveUrl(url, location);
      if (next == url || hop >= 4) {
        throw _refused(response, notFoundErrorMarker, 'Too many redirects for $url');
      }

      return _get(next, hop: hop + 1);
    }

    return response;
  }

  static void _mergeSetCookies(Response<String> response, Map<String, String> target) {
    final List<String>? setCookies = response.headers[HttpHeaders.setCookieHeader];
    if (setCookies == null) {
      return;
    }

    for (final String header in setCookies) {
      try {
        final Cookie parsed = Cookie.fromSetCookieValue(header);
        final String name = parsed.name.trim();
        final String value = parsed.value.trim();
        if (name.isEmpty) {
          continue;
        }
        if (value.isEmpty || value.toLowerCase() == 'deleted') {
          target.remove(name);
        } else {
          target[name] = value;
        }
      } catch (_) {
        // Fallback parser for malformed Set-Cookie attributes.
        final String pair = header.split(';').first;
        final int sep = pair.indexOf('=');
        if (sep <= 0) {
          continue;
        }
        final String name = pair.substring(0, sep).trim();
        final String value = pair.substring(sep + 1).trim();
        if (value.isEmpty || value.toLowerCase() == 'deleted') {
          target.remove(name);
        } else {
          target[name] = value;
        }
      }
    }
  }

  static String? _cookieValueIgnoreCase(Map<String, String> cookies, String name) {
    final String lower = name.toLowerCase();
    for (final MapEntry<String, String> entry in cookies.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  static String _formatCookieHeader(Map<String, String> cookies) {
    return cookies.entries.map((MapEntry<String, String> e) => '${e.key}=${e.value}').join('; ');
  }

  static bool _isCloudflareHtml(String html) =>
      html.contains('Just a moment') || html.contains('_cf_chl_opt');

  /// Resolves a `Location` header.
  ///
  /// Dart decodes header values as latin1, so a raw UTF-8 slug arrives as
  /// mojibake (`â\u0080\u0099` instead of `’`). It is repaired back to UTF-8
  /// before the URI is built, otherwise the request would be double-encoded and
  /// the site would answer with another redirect.
  static String _resolveUrl(String base, String location) {
    final String decoded = _repairHeaderEncoding(location);
    try {
      return Uri.parse(base).resolve(decoded).toString();
    } catch (_) {
      return Uri.parse(base).resolve(Uri.encodeFull(decoded)).toString();
    }
  }

  static String _repairHeaderEncoding(String value) {
    if (!value.contains(RegExp(r'[\u0080-\u00FF]'))) {
      return value;
    }

    try {
      return utf8.decode(latin1.encode(value));
    } catch (_) {
      return value;
    }
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

    if (_isCloudflareHtml(html)) {
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
