/// A tag, artist, parody or group of https://xlecx.one.
///
/// `slug` is the value the site puts in its filter path (`n.m.tags=big ass`,
/// `artist=kawer`), `label` is the human name shown on the cards and on the
/// detail page.
class XlecxTag {
  final String slug;
  final String label;
  final XlecxTagKind kind;

  /// Number of publications, when the directory exposes it.
  final int count;

  const XlecxTag({
    required this.slug,
    required this.label,
    this.kind = XlecxTagKind.tag,
    this.count = 0,
  });

  String get normalizedLabel => normalizeLabelOf(label);

  static String normalizeLabelOf(String value) => value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  bool operator ==(Object other) => identical(this, other) || other is XlecxTag && other.slug == slug && other.kind == kind;

  @override
  int get hashCode => Object.hash(slug, kind);

  @override
  String toString() => 'XlecxTag{kind: $kind, slug: $slug, label: $label, count: $count}';
}

enum XlecxTagKind { tag, artist, parody, group }

/// Sections of the site's listing. Video sections (18 and 20) are deliberately
/// left out: Acervo H&C only reads image galleries.
enum XlecxCategory {
  all(null, 'All'),
  comics(1, 'Comics'),
  manga(13, 'Manga'),
  pictures(15, 'Pictures'),
  threeD(3, '3D comics'),
  animeParody(2, 'Anime Parody'),
  cartoonParody(4, 'Cartoon Parody'),
  gamesParody(10, 'Games Parody'),
  furry(5, 'Furry'),
  incest(6, 'Incest'),
  dickgirl(9, 'Dickgirl'),
  yaoi(11, 'Yaoi | Gay'),
  yuri(12, 'Yuri | Lesbian');

  final int? id;

  /// Values are site-native, so they are not translated.
  final String label;

  const XlecxCategory(this.id, this.label);

  static XlecxCategory? fromLabel(String value) {
    final String normalized = XlecxTag.normalizeLabelOf(value);
    for (final XlecxCategory category in XlecxCategory.values) {
      if (category != XlecxCategory.all && XlecxTag.normalizeLabelOf(category.label) == normalized) {
        return category;
      }
    }
    return null;
  }
}

/// Sort keys of the site's `sort=` filter, with the direction the listing form
/// uses for each one.
enum XlecxSort { newest, recentlyUpdated, topRated, mostViewed, mostCommented, titleAZ }

extension XlecxSortX on XlecxSort {
  String get apiValue => switch (this) {
        XlecxSort.newest => 'date',
        XlecxSort.recentlyUpdated => 'editdate',
        XlecxSort.topRated => 'rating',
        XlecxSort.mostViewed => 'news_read',
        XlecxSort.mostCommented => 'comm_num',
        XlecxSort.titleAZ => 'title',
      };

  String get order => this == XlecxSort.titleAZ ? 'asc' : 'desc';

  String get labelKey => switch (this) {
        XlecxSort.newest => 'newest',
        XlecxSort.recentlyUpdated => 'lastUpdated',
        XlecxSort.topRated => 'topRated',
        XlecxSort.mostViewed => 'mostViewed',
        XlecxSort.mostCommented => 'mostCommented',
        XlecxSort.titleAZ => 'titleAZ',
      };
}

/// Everything the Xlecx page can filter by.
///
/// Execution rules:
/// - keyword                -> the site search (`index.php?do=search`), which
///   ignores every other filter (the site itself works that way);
/// - otherwise              -> the `/f/` listing built from category, tags,
///   artist/parody and sort. The path is emitted in the site's canonical order
///   so no extra 301 round trip is needed.
class XlecxSearchConfig {
  String keyword;
  final List<XlecxTag> includeTags;
  final List<XlecxTag> excludeTags;
  XlecxTag? artist;
  XlecxTag? parody;
  XlecxTag? group;
  XlecxCategory category;
  XlecxSort sort;

  XlecxSearchConfig({
    this.keyword = '',
    List<XlecxTag>? includeTags,
    List<XlecxTag>? excludeTags,
    this.artist,
    this.parody,
    this.group,
    this.category = XlecxCategory.all,
    this.sort = XlecxSort.newest,
  })  : includeTags = includeTags ?? <XlecxTag>[],
        excludeTags = excludeTags ?? <XlecxTag>[];

  bool get hasKeyword => keyword.trim().isNotEmpty;

  bool get hasTags => includeTags.isNotEmpty || excludeTags.isNotEmpty;

  bool get hasMediaFilters => hasTags || artist != null || parody != null || group != null || category != XlecxCategory.all;

  /// True when the request must go to the site search instead of a `/f/` path.
  bool get isSearchMode => hasKeyword;

  /// True when anything filters the listing (used to hide the listing tabs).
  bool get isFiltering => isSearchMode || hasMediaFilters || sort != XlecxSort.newest;

  int get activeFilterCount =>
      includeTags.length +
      excludeTags.length +
      (artist != null ? 1 : 0) +
      (parody != null ? 1 : 0) +
      (group != null ? 1 : 0) +
      (category != XlecxCategory.all ? 1 : 0);

  XlecxSearchConfig copy() {
    return XlecxSearchConfig(
      keyword: keyword,
      includeTags: List<XlecxTag>.of(includeTags),
      excludeTags: List<XlecxTag>.of(excludeTags),
      artist: artist,
      parody: parody,
      group: group,
      category: category,
      sort: sort,
    );
  }

  void reset() {
    keyword = '';
    includeTags.clear();
    excludeTags.clear();
    artist = null;
    parody = null;
    group = null;
    category = XlecxCategory.all;
    sort = XlecxSort.newest;
  }

  @override
  String toString() {
    return 'XlecxSearchConfig{keyword: $keyword, include: $includeTags, exclude: $excludeTags, artist: $artist, parody: $parody, group: $group, category: $category, sort: $sort}';
  }
}
