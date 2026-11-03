import 'package:acervo_hc/src/exception/internal_exception.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';

class GalleryUrl {
  /// E-Hentai (true) or EXHentai (false). Always false for external sources.
  final bool isEH;

  /// Which site this url belongs to.
  final GallerySource source;

  /// Acervo H&C-wide id: the E-Hentai gid, or [eightMusesGid] for external ones.
  final int gid;

  /// E-Hentai gallery token, or the external id as string.
  final String token;

  /// 8muses gallery id (only set for [GallerySource.eightMuses]).
  final int? externalId;

  const GalleryUrl({
    required this.isEH,
    required this.gid,
    required this.token,
    this.source = GallerySource.eh,
    this.externalId,
  }) : assert(source != GallerySource.eh || token.length == 10);

  static final RegExp _ehRegExp = RegExp(r'https://e([-x])hentai\.org/g/(\d+)/([a-z0-9]{10})');
  static final RegExp _eightMusesRegExp = RegExp(r'https?://(?:www\.)?8muses\.io/g/(\d+)');

  static GalleryUrl? tryParse(String url) {
    Match? match = _ehRegExp.firstMatch(url);
    if (match != null) {
      return GalleryUrl(
        isEH: match.group(1) == '-',
        gid: int.parse(match.group(2)!),
        token: match.group(3)!,
      );
    }

    match = _eightMusesRegExp.firstMatch(url);
    if (match != null) {
      return eightMusesGalleryUrl(int.parse(match.group(1)!));
    }

    return null;
  }

  static GalleryUrl parse(String url) {
    GalleryUrl? galleryUrl = tryParse(url);
    if (galleryUrl == null) {
      throw InternalException(message: 'Parse gallery url failed, url:$url');
    }
    return galleryUrl;
  }

  /// Build the url of an external 8muses gallery.
  static GalleryUrl eightMusesGalleryUrl(int externalId) {
    return GalleryUrl(
      isEH: false,
      source: GallerySource.eightMuses,
      gid: eightMusesGid(externalId),
      token: externalId.toString(),
      externalId: externalId,
    );
  }

  String get url {
    if (source == GallerySource.eightMuses) {
      return 'https://8muses.io/g/$externalId';
    }
    return isEH ? 'https://e-hentai.org/g/$gid/$token/' : 'https://exhentai.org/g/$gid/$token/';
  }

  GalleryUrl copyWith({
    bool? isEH,
    GallerySource? source,
    int? gid,
    String? token,
    int? externalId,
  }) {
    return GalleryUrl(
      isEH: isEH ?? this.isEH,
      source: source ?? this.source,
      gid: gid ?? this.gid,
      token: token ?? this.token,
      externalId: externalId ?? this.externalId,
    );
  }

  @override
  String toString() {
    return 'GalleryUrl{source: $source, isEH: $isEH, gid: $gid, token: $token, externalId: $externalId}';
  }
}
