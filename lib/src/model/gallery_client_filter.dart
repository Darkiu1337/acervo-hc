import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';

/// Client-side sort orders for local lists (Already Read, Local Favorites, etc.).
enum GallerySortOption {
  recent('sortRecent'),
  titleAsc('sortTitleAsc'),
  titleDesc('sortTitleDesc'),
  pagesDesc('sortPagesDesc'),
  pagesAsc('sortPagesAsc'),
  ;

  final String labelKey;
  const GallerySortOption(this.labelKey);
}

/// Client-side filter and optional sorter for pages without native filtering
/// (Popular, Ranklist, Already Read, and Local Favorites).
class GalleryClientFilter {
  static const List<String> allCategories = <String>[
    'Doujinshi',
    'Manga',
    'Artist CG',
    'Game CG',
    'Western',
    'Non-H',
    'Image Set',
    'Cosplay',
    'Asian Porn',
    'Misc',
  ];

  static const List<String> commonLanguages = <String>[
    'portuguese',
    'english',
    'japanese',
    'chinese',
    'spanish',
    'korean',
  ];

  final String keyword;
  final Set<String> disabledCategories;
  final String? language;

  /// When non-empty, only galleries from these providers match.
  final Set<GallerySource> sources;

  final GallerySortOption sortOrder;

  const GalleryClientFilter({
    this.keyword = '',
    this.disabledCategories = const <String>{},
    this.language,
    this.sources = const <GallerySource>{},
    this.sortOrder = GallerySortOption.recent,
  });

  bool get hasFilter =>
      keyword.trim().isNotEmpty ||
      disabledCategories.isNotEmpty ||
      (language != null && language!.trim().isNotEmpty) ||
      sources.isNotEmpty;

  bool get isActive => hasFilter || sortOrder != GallerySortOption.recent;

  GalleryClientFilter copyWith({
    String? keyword,
    Set<String>? disabledCategories,
    String? language,
    bool clearLanguage = false,
    Set<GallerySource>? sources,
    GallerySortOption? sortOrder,
  }) {
    return GalleryClientFilter(
      keyword: keyword ?? this.keyword,
      disabledCategories: disabledCategories ?? this.disabledCategories,
      language: clearLanguage ? null : (language ?? this.language),
      sources: sources ?? this.sources,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Returns true when [gallery] satisfies all active client-side criteria.
  bool matches(Gallery gallery) {
    if (!hasFilter) {
      return true;
    }

    if (sources.isNotEmpty && !sources.contains(gallery.galleryUrl.source)) {
      return false;
    }

    if (disabledCategories.isNotEmpty) {
      final String cat = gallery.category.trim().toLowerCase();
      for (final String disabled in disabledCategories) {
        if (disabled.toLowerCase() == cat) {
          return false;
        }
      }
    }

    if (language != null && language!.trim().isNotEmpty) {
      final String wanted = language!.trim().toLowerCase();
      final String galLang = (gallery.language ?? '').trim().toLowerCase();
      bool matchedLang = galLang == wanted;
      if (!matchedLang) {
        final List<GalleryTag>? langTags = gallery.tags['language'];
        if (langTags != null) {
          matchedLang = langTags.any((t) => t.tagData.key.toLowerCase() == wanted);
        }
      }
      if (!matchedLang) {
        return false;
      }
    }

    final String trimmed = keyword.trim();
    if (trimmed.isNotEmpty) {
      final String haystack = _buildHaystack(gallery);
      final List<String> tokens =
          trimmed.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      for (final String token in tokens) {
        if (token.startsWith('-') && token.length > 1) {
          final String excluded = token.substring(1);
          if (haystack.contains(excluded)) {
            return false;
          }
        } else {
          if (!haystack.contains(token)) {
            return false;
          }
        }
      }
    }

    return true;
  }

  List<Gallery> apply(List<Gallery> source) {
    final List<Gallery> result = hasFilter ? source.where(matches).toList() : List<Gallery>.from(source);
    if (sortOrder != GallerySortOption.recent) {
      sortList(result, sortOrder);
    }
    return result;
  }

  static void sortList(List<Gallery> galleries, GallerySortOption order) {
    switch (order) {
      case GallerySortOption.recent:
        return;
      case GallerySortOption.titleAsc:
        galleries.sort((Gallery a, Gallery b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        return;
      case GallerySortOption.titleDesc:
        galleries.sort((Gallery a, Gallery b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        return;
      case GallerySortOption.pagesDesc:
        galleries.sort((Gallery a, Gallery b) => (b.pageCount ?? -1).compareTo(a.pageCount ?? -1));
        return;
      case GallerySortOption.pagesAsc:
        galleries.sort((Gallery a, Gallery b) => (a.pageCount ?? 1 << 30).compareTo(b.pageCount ?? 1 << 30));
        return;
    }
  }

  static String _buildHaystack(Gallery gallery) {
    final StringBuffer sb = StringBuffer()
      ..write(gallery.title.toLowerCase())
      ..write(' ')
      ..write((gallery.altTitle ?? '').toLowerCase())
      ..write(' ')
      ..write((gallery.uploader ?? '').toLowerCase())
      ..write(' ')
      ..write(gallery.category.toLowerCase())
      ..write(' ')
      ..write((gallery.language ?? '').toLowerCase());
    for (final MapEntry<String, List<GalleryTag>> entry in gallery.tags.entries) {
      for (final GalleryTag tag in entry.value) {
        sb
          ..write(' ')
          ..write(entry.key.toLowerCase())
          ..write(':')
          ..write(tag.tagData.key.toLowerCase());
        if (tag.tagData.tagName != null && tag.tagData.tagName!.isNotEmpty) {
          sb
            ..write(' ')
            ..write(tag.tagData.tagName!.toLowerCase());
        }
      }
    }
    return sb.toString();
  }
}
