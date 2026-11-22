import 'dart:collection';

import 'package:acervo_hc/src/database/database.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';

/// Sort orders supported by nhentai API v2.
enum NHentaiSort {
  recent('date', 'nhentaiSortRecent'),
  popularToday('popular-today', 'nhentaiSortPopularToday'),
  popularWeek('popular-week', 'nhentaiSortPopularWeek'),
  popularAll('popular', 'nhentaiSortPopularAll');

  final String apiValue;
  final String labelKey;

  const NHentaiSort(this.apiValue, this.labelKey);
}

/// Quick language filter chips for the nhentai tab.
enum NHentaiLanguage {
  all('', 'all'),
  english('language:english', 'english'),
  japanese('language:japanese', 'japanese'),
  chinese('language:chinese', 'chinese');

  final String queryClause;
  final String labelKey;

  const NHentaiLanguage(this.queryClause, this.labelKey);
}

/// CDN host pools returned by `GET /api/v2/cdn`.
class NHentaiCdnConfig {
  static const NHentaiCdnConfig fallback = NHentaiCdnConfig(
    imageServers: <String>[
      'https://i1.nhentai.net',
      'https://i2.nhentai.net',
      'https://i3.nhentai.net',
      'https://i4.nhentai.net',
    ],
    thumbServers: <String>[
      'https://t1.nhentai.net',
      'https://t2.nhentai.net',
      'https://t3.nhentai.net',
      'https://t4.nhentai.net',
    ],
  );

  final List<String> imageServers;
  final List<String> thumbServers;

  const NHentaiCdnConfig({
    required this.imageServers,
    required this.thumbServers,
  });

  factory NHentaiCdnConfig.fromJson(Map<String, dynamic> json) {
    final List<String> images = _parseServers(json['image_servers']);
    final List<String> thumbs = _parseServers(json['thumb_servers']);
    return NHentaiCdnConfig(
      imageServers: images.isEmpty ? fallback.imageServers : images,
      thumbServers: thumbs.isEmpty ? fallback.thumbServers : thumbs,
    );
  }

  static List<String> _parseServers(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .map((dynamic e) => e.toString().trim())
        .where((String s) => s.startsWith('http://') || s.startsWith('https://'))
        .map((String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s)
        .toList();
  }

  /// Resolves a relative API v2 image path (e.g. `galleries/4345864/1.webp`)
  /// against a deterministic CDN host so Flutter's image cache key stays stable.
  String resolveImageUrl(String path, {int seed = 0}) {
    return _resolve(path, imageServers, seed);
  }

  /// Resolves a relative API v2 thumbnail/cover path against a deterministic
  /// thumbnail CDN host.
  String resolveThumbUrl(String path, {int seed = 0}) {
    return _resolve(path, thumbServers, seed);
  }

  static String _resolve(String path, List<String> hosts, int seed) {
    final String trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final String cleanPath = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    final String host = hosts[seed.abs() % hosts.length];
    return '$host/$cleanPath';
  }
}

/// Tag entry returned by `GET /api/v2/galleries/{id}`.
class NHentaiTag {
  final int id;
  final String type;
  final String name;
  final String slug;
  final int count;

  const NHentaiTag({
    required this.id,
    required this.type,
    required this.name,
    required this.slug,
    required this.count,
  });

  factory NHentaiTag.fromJson(Map<String, dynamic> json) {
    return NHentaiTag(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: (json['type'] as String? ?? 'tag').toLowerCase(),
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Query token understood by `/api/v2/search`, e.g. `artist:"nanohana"` or
  /// `tag:"big breasts"`.
  String get searchToken {
    final String escaped = name.replaceAll('"', '');
    return escaped.contains(' ') ? '$type:"$escaped"' : '$type:$escaped';
  }

  @override
  bool operator ==(Object other) => other is NHentaiTag && id == other.id && type == other.type && name == other.name;

  @override
  int get hashCode => Object.hash(id, type, name);
}

/// One resolved page image and thumbnail inside an nhentai gallery.
class NHentaiPageImage {
  final int number;
  final String imageUrl;
  final String thumbUrl;
  final int width;
  final int height;

  const NHentaiPageImage({
    required this.number,
    required this.imageUrl,
    required this.thumbUrl,
    required this.width,
    required this.height,
  });
}

/// Listing summary item returned by `/api/v2/galleries`, `/api/v2/search`, and
/// `/api/v2/galleries/{id}/related`.
class NHentaiGallerySummary {
  final int id;
  final String mediaId;
  final String englishTitle;
  final String japaneseTitle;
  final String thumbUrl;
  final int thumbWidth;
  final int thumbHeight;
  final int numPages;
  final int numFavorites;

  const NHentaiGallerySummary({
    required this.id,
    required this.mediaId,
    required this.englishTitle,
    required this.japaneseTitle,
    required this.thumbUrl,
    required this.thumbWidth,
    required this.thumbHeight,
    required this.numPages,
    required this.numFavorites,
  });

  factory NHentaiGallerySummary.fromJson(Map<String, dynamic> json, NHentaiCdnConfig cdn) {
    final int id = (json['id'] as num).toInt();
    final String rawThumb = json['thumbnail'] as String? ?? '';
    return NHentaiGallerySummary(
      id: id,
      mediaId: (json['media_id'] ?? '').toString(),
      englishTitle: (json['english_title'] as String? ?? '').trim(),
      japaneseTitle: (json['japanese_title'] as String? ?? '').trim(),
      thumbUrl: cdn.resolveThumbUrl(rawThumb, seed: id),
      thumbWidth: (json['thumbnail_width'] as num?)?.toInt() ?? 250,
      thumbHeight: (json['thumbnail_height'] as num?)?.toInt() ?? 350,
      numPages: (json['num_pages'] as num?)?.toInt() ?? 0,
      numFavorites: (json['num_favorites'] as num?)?.toInt() ?? 0,
    );
  }

  Gallery toGallery({bool preferJapaneseTitle = false}) {
    final String primary = preferJapaneseTitle
        ? (japaneseTitle.isNotEmpty ? japaneseTitle : englishTitle)
        : (englishTitle.isNotEmpty ? englishTitle : japaneseTitle);
    final String secondary = preferJapaneseTitle ? englishTitle : japaneseTitle;
    final String? alt = (secondary.isNotEmpty && secondary != primary) ? secondary : null;

    return Gallery(
      galleryUrl: GalleryUrl.nhentaiGalleryUrl(id),
      title: primary.isEmpty ? '#$id' : primary,
      altTitle: alt,
      category: 'nhentai',
      cover: GalleryImage(
        url: thumbUrl,
        width: thumbWidth.toDouble(),
        height: thumbHeight.toDouble(),
      ),
      pageCount: numPages > 0 ? numPages : null,
      rating: 0,
      hasRated: false,
      publishTime: '',
      isExpunged: false,
      tags: LinkedHashMap<String, List<GalleryTag>>(),
    );
  }
}

/// Paginated listing result from nhentai API v2.
class NHentaiSearchPage {
  final List<NHentaiGallerySummary> items;
  final int currentPage;
  final int totalPages;
  final int totalCount;

  const NHentaiSearchPage({
    required this.items,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
  });

  bool get hasMore => currentPage < totalPages && items.isNotEmpty;
}

/// Full gallery payload returned by `GET /api/v2/galleries/{id}`.
class NHentaiGalleryDetail {
  final int id;
  final String mediaId;
  final String englishTitle;
  final String japaneseTitle;
  final String prettyTitle;
  final String coverUrl;
  final String thumbUrl;
  final int uploadTimestamp;
  final int numPages;
  final int numFavorites;
  final List<NHentaiTag> tags;
  final List<NHentaiPageImage> pages;

  const NHentaiGalleryDetail({
    required this.id,
    required this.mediaId,
    required this.englishTitle,
    required this.japaneseTitle,
    required this.prettyTitle,
    required this.coverUrl,
    required this.thumbUrl,
    required this.uploadTimestamp,
    required this.numPages,
    required this.numFavorites,
    required this.tags,
    required this.pages,
  });

  factory NHentaiGalleryDetail.fromJson(Map<String, dynamic> json, NHentaiCdnConfig cdn) {
    final int id = (json['id'] as num).toInt();
    final Map<String, dynamic> titleMap =
        json['title'] is Map ? Map<String, dynamic>.from(json['title'] as Map) : const <String, dynamic>{};
    final Map<String, dynamic> coverMap =
        json['cover'] is Map ? Map<String, dynamic>.from(json['cover'] as Map) : const <String, dynamic>{};
    final Map<String, dynamic> thumbMap =
        json['thumbnail'] is Map ? Map<String, dynamic>.from(json['thumbnail'] as Map) : const <String, dynamic>{};

    final List<NHentaiTag> parsedTags = (json['tags'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map raw) => NHentaiTag.fromJson(Map<String, dynamic>.from(raw)))
        .where((NHentaiTag tag) => tag.name.isNotEmpty)
        .toList();

    final List<NHentaiPageImage> parsedPages = <NHentaiPageImage>[];
    final List<dynamic> rawPages = json['pages'] as List? ?? const <dynamic>[];
    for (int i = 0; i < rawPages.length; i++) {
      final dynamic entry = rawPages[i];
      if (entry is! Map) {
        continue;
      }
      final Map<String, dynamic> pageMap = Map<String, dynamic>.from(entry);
      final int number = (pageMap['number'] as num?)?.toInt() ?? (i + 1);
      final String path = pageMap['path'] as String? ?? '';
      final String thumbPath = pageMap['thumbnail'] as String? ?? '';
      if (path.isEmpty) {
        continue;
      }
      final String imageUrl = cdn.resolveImageUrl(path, seed: id + number);
      final String pageThumbUrl = thumbPath.isNotEmpty ? cdn.resolveThumbUrl(thumbPath, seed: id + number) : imageUrl;
      parsedPages.add(
        NHentaiPageImage(
          number: number,
          imageUrl: imageUrl,
          thumbUrl: pageThumbUrl,
          width: (pageMap['width'] as num?)?.toInt() ?? 0,
          height: (pageMap['height'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    final String coverPath = coverMap['path'] as String? ?? '';
    final String thumbPath = thumbMap['path'] as String? ?? '';

    return NHentaiGalleryDetail(
      id: id,
      mediaId: (json['media_id'] ?? '').toString(),
      englishTitle: (titleMap['english'] as String? ?? '').trim(),
      japaneseTitle: (titleMap['japanese'] as String? ?? '').trim(),
      prettyTitle: (titleMap['pretty'] as String? ?? '').trim(),
      coverUrl: cdn.resolveThumbUrl(coverPath.isNotEmpty ? coverPath : thumbPath, seed: id),
      thumbUrl: cdn.resolveThumbUrl(thumbPath.isNotEmpty ? thumbPath : coverPath, seed: id),
      uploadTimestamp: (json['upload_date'] as num?)?.toInt() ?? 0,
      numPages: (json['num_pages'] as num?)?.toInt() ?? parsedPages.length,
      numFavorites: (json['num_favorites'] as num?)?.toInt() ?? 0,
      tags: parsedTags,
      pages: parsedPages,
    );
  }

  GalleryUrl get galleryUrl => GalleryUrl.nhentaiGalleryUrl(id);

  String displayTitle({bool preferJapaneseTitle = false}) {
    final String primary = preferJapaneseTitle
        ? (japaneseTitle.isNotEmpty ? japaneseTitle : englishTitle)
        : (englishTitle.isNotEmpty ? englishTitle : japaneseTitle);
    if (primary.isNotEmpty) {
      return primary;
    }
    return prettyTitle.isNotEmpty ? prettyTitle : '#$id';
  }

  String? alternateTitle({bool preferJapaneseTitle = false}) {
    final String primary = displayTitle(preferJapaneseTitle: preferJapaneseTitle);
    final String candidate = preferJapaneseTitle ? englishTitle : japaneseTitle;
    if (candidate.isNotEmpty && candidate != primary) {
      return candidate;
    }
    return null;
  }

  List<NHentaiTag> tagsOfType(String type) => tags.where((NHentaiTag t) => t.type == type).toList();

  List<String> get artistNames => tagsOfType('artist').map((NHentaiTag t) => t.name).toList();

  List<String> get groupNames => tagsOfType('group').map((NHentaiTag t) => t.name).toList();

  String get categoryLabel {
    final List<NHentaiTag> cats = tagsOfType('category');
    if (cats.isEmpty) {
      return 'nhentai';
    }
    final String name = cats.first.name;
    return name.isEmpty ? 'nhentai' : '${name[0].toUpperCase()}${name.substring(1)}';
  }

  String get languageLabel {
    final List<NHentaiTag> langs = tagsOfType('language').where((NHentaiTag t) => t.name != 'translated').toList();
    if (langs.isEmpty) {
      return '';
    }
    return langs.first.name;
  }

  String get formattedUploadDate {
    if (uploadTimestamp <= 0) {
      return '';
    }
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(uploadTimestamp * 1000, isUtc: true).toLocal();
    final String y = dt.year.toString().padLeft(4, '0');
    final String m = dt.month.toString().padLeft(2, '0');
    final String d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  List<String> get pageUrls => pages.map((NHentaiPageImage p) => p.imageUrl).toList();

  List<String> get pageThumbUrls => pages.map((NHentaiPageImage p) => p.thumbUrl).toList();

  LinkedHashMap<String, List<GalleryTag>> toGalleryTags() {
    final LinkedHashMap<String, List<GalleryTag>> map = LinkedHashMap<String, List<GalleryTag>>();
    for (final NHentaiTag tag in tags) {
      final String ns = tag.type == 'tag' ? 'misc' : tag.type;
      (map[ns] ??= <GalleryTag>[]).add(GalleryTag(tagData: TagData(namespace: ns, key: tag.name)));
    }
    return map;
  }

  Gallery toGallery({bool preferJapaneseTitle = false}) {
    final List<String> creators = <String>[...artistNames, ...groupNames];
    return Gallery(
      galleryUrl: galleryUrl,
      title: displayTitle(preferJapaneseTitle: preferJapaneseTitle),
      altTitle: alternateTitle(preferJapaneseTitle: preferJapaneseTitle),
      category: categoryLabel,
      cover: GalleryImage(url: thumbUrl.isNotEmpty ? thumbUrl : coverUrl),
      pageCount: pages.isNotEmpty ? pages.length : numPages,
      rating: 0,
      hasRated: false,
      language: languageLabel,
      uploader: creators.join(', '),
      publishTime: formattedUploadDate,
      isExpunged: false,
      tags: toGalleryTags(),
    );
  }

  GalleryHistoryModel toHistoryModel({bool preferJapaneseTitle = false}) {
    final List<String> creators = <String>[...artistNames, ...groupNames];
    return GalleryHistoryModel(
      galleryUrl: galleryUrl,
      title: displayTitle(preferJapaneseTitle: preferJapaneseTitle),
      altTitle: alternateTitle(preferJapaneseTitle: preferJapaneseTitle),
      category: categoryLabel,
      coverUrl: thumbUrl.isNotEmpty ? thumbUrl : coverUrl,
      pageCount: pages.isNotEmpty ? pages.length : numPages,
      rating: 0,
      language: languageLabel,
      uploader: creators.join(', '),
      publishTime: formattedUploadDate,
      isExpunged: false,
      tags: tags.map((NHentaiTag t) => '${t.type}:${t.name}').toList(),
    );
  }
}

/// Parses a direct nhentai gallery id from inputs like `699178`, `#699178`,
/// or `https://nhentai.net/g/699178/`.
int? tryParseNHentaiCode(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final RegExpMatch? codeMatch = RegExp(r'^#?(\d{1,8})$').firstMatch(trimmed);
  if (codeMatch != null) {
    final int? parsed = int.tryParse(codeMatch.group(1)!);
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  final GalleryUrl? parsedUrl = GalleryUrl.tryParse(trimmed);
  if (parsedUrl != null && parsedUrl.externalId != null && trimmed.toLowerCase().contains('nhentai.net')) {
    return parsedUrl.externalId;
  }

  return null;
}

/// Minimal placeholder [Gallery] used when opening an nhentai url directly from
/// the clipboard or launch arguments before the API payload has been fetched.
Gallery nhentaiGalleryFromUrl(GalleryUrl url) {
  final int id = url.externalId ?? 0;
  return Gallery(
    galleryUrl: url,
    title: '#$id',
    category: 'nhentai',
    cover: GalleryImage(url: ''),
    rating: 0,
    hasRated: false,
    publishTime: '',
    isExpunged: false,
    tags: LinkedHashMap<String, List<GalleryTag>>(),
  );
}
