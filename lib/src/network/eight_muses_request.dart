import 'package:dio/dio.dart';
import 'package:acervo_hc/src/model/eight_muses_detail.dart';
import 'package:acervo_hc/src/model/eight_muses_search.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/setting/network_setting.dart';
import 'package:acervo_hc/src/utils/eight_muses_parser.dart';

/// Listings exposed by the site's navigation bar.
enum EightMusesListing { popular, newest, browse }

/// HTTP client for https://8muses.io.
///
/// Deliberately separate from the E-H request layer: no E-H cookies, no domain
/// fronting and no E-H cache manager. The site needs neither authentication nor
/// a Cloudflare clearance, so a plain Dio instance is enough.
class EightMusesRequest {
  static const String baseUrl = EightMusesParser.baseUrl;

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  Dio? _dio;

  Dio get dio => _dio ??= _createDio();

  Dio _createDio() {
    return Dio(
      BaseOptions(
        connectTimeout: Duration(milliseconds: networkSetting.connectTimeout.value),
        receiveTimeout: Duration(milliseconds: networkSetting.receiveTimeout.value),
        headers: <String, dynamic>{
          'User-Agent': _userAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ),
    );
  }

  Future<List<Gallery>> requestListing({required EightMusesListing listing, required int page}) async {
    final String path = switch (listing) {
      EightMusesListing.popular => page <= 1 ? '/popular' : '/popular/page/$page',
      EightMusesListing.newest => page <= 1 ? '/new' : '/new/page/$page',
      EightMusesListing.browse => page <= 1 ? '/browse' : '/browse/page/$page',
    };

    return _requestGalleryPage(path);
  }

  Future<List<Gallery>> search({required EightMusesSearchConfig config, required int page}) async {
    final Map<String, String> params = <String, String>{
      if (config.hasKeyword) 'q': config.keyword.trim(),
      'sort': config.sort.apiValue,
    };

    final String query = Uri(queryParameters: params).query;
    final String path = page <= 1 ? '/search?$query' : '/search/page/$page?$query';
    return _requestGalleryPage(path);
  }

  /// A tag listing, used as the base when include tags are selected.
  Future<List<Gallery>> requestTagPage({required String tagSlug, required int page}) {
    final String path = page <= 1 ? '/tag/$tagSlug' : '/tag/$tagSlug/page/$page';
    return _requestGalleryPage(path);
  }

  /// An artist listing (`/artist/<slug>`), paginated like the other listings.
  Future<List<Gallery>> requestArtistPage({required String artistSlug, required int page}) {
    final String path = page <= 1 ? '/artist/$artistSlug' : '/artist/$artistSlug/page/$page';
    return _requestGalleryPage(path);
  }

  /// Tag directory of `/genres`.
  Future<List<EightMusesTag>> requestTags() async {
    final Response<String> response = await dio.get<String>(
      '$baseUrl/genres',
      options: Options(responseType: ResponseType.plain),
    );

    return EightMusesParser.parseTags(response.data ?? '');
  }

  /// Artist directory of `/artists`.
  Future<List<EightMusesTag>> requestArtists() async {
    final Response<String> response = await dio.get<String>(
      '$baseUrl/artists',
      options: Options(responseType: ResponseType.plain),
    );

    return EightMusesParser.parseArtists(response.data ?? '');
  }

  Future<EightMusesDetail> requestDetail(int id) async {
    final Response<String> response = await dio.get<String>(
      '$baseUrl/g/$id',
      options: Options(responseType: ResponseType.plain),
    );

    final EightMusesDetail? detail = EightMusesParser.parseDetail(response.data ?? '', id);
    if (detail == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        error: 'Unable to parse 8muses gallery #$id',
        type: DioExceptionType.badResponse,
        response: response,
      );
    }

    return detail;
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

  Future<List<Gallery>> _requestGalleryPage(String path) async {
    final Response<String> response = await dio.get<String>(
      '$baseUrl$path',
      options: Options(responseType: ResponseType.plain),
    );

    return EightMusesParser.parseGalleryList(response.data ?? '');
  }
}

final EightMusesRequest eightMusesRequest = EightMusesRequest();
