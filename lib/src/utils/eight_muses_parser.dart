import 'dart:collection';
import 'dart:convert';

import 'package:acervo_hc/src/model/eight_muses_detail.dart';
import 'package:acervo_hc/src/model/eight_muses_search.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:intl/intl.dart';

/// Parsers for https://8muses.io.
///
/// Two data sources are available on every page and both are used here:
///
/// 1. plain HTML — server rendered cards (`<a class="grid-card" href="/g/ID">`)
///    and the `<script type="application/ld+json">` block of a gallery page;
/// 2. the Next.js RSC flight payload embedded in the page (`\"id\":\"16140\"`),
///    which carries `pages`, `rating`, `author` and `updated` even when the
///    JSON-LD block does not.
///
/// JSON-LD is authoritative when present; the RSC payload is the fallback.
class EightMusesParser {
  static const String baseUrl = 'https://8muses.io';

  /// Full size page image. The server 404s for `pageNo > pageCount`.
  static String pageUrl(int id, int pageNo) => '$baseUrl/api/legacy-media/$id/$pageNo';

  /// Small variant used by the reader's thumbnail strip.
  static String thumbUrl(int id, int pageNo) => '${pageUrl(id, pageNo)}?variant=thumbnail';

  static String coverUrl(int id) => '$baseUrl/api/legacy-media/$id/cover';

  static GalleryUrl galleryUrlOf(int id) => GalleryUrl.eightMusesGalleryUrl(id);

  static final RegExp _cardRegExp = RegExp(r'<a class="grid-card" href="/g/(\d+)">([\s\S]*?)</a>');
  static final RegExp _titleAttrRegExp = RegExp(r'<strong[^>]*title="([^"]*)"');
  static final RegExp _strongTextRegExp = RegExp(r'<strong[^>]*>([^<]*)</strong>');
  static final RegExp _ariaLabelRegExp = RegExp(r'aria-label="([^"]*)"');
  static final RegExp _ldJsonRegExp = RegExp(r'<script type="application/ld\+json"[^>]*>([\s\S]*?)</script>');

  // RSC payload fragments are escaped, so a key looks like \"pages\":\"12\".
  static final RegExp _rscIdRegExp = RegExp(r'\\"id\\":\\"(\d+)\\"');

  /// Gallery cards of a listing/search page, in page order.
  static List<Gallery> parseGalleryList(String html) {
    final List<Gallery> galleries = <Gallery>[];
    final Set<int> seen = <int>{};
    final Map<int, int> pages = parsePagesMap(html);
    final Map<int, List<String>> genres = parseGenresMap(html);

    for (final Match match in _cardRegExp.allMatches(html)) {
      final int? id = int.tryParse(match.group(1) ?? '');
      if (id == null || !seen.add(id)) {
        continue;
      }

      final String body = match.group(2) ?? '';
      final String rawTitle = _firstGroup(_titleAttrRegExp, body) ??
          _firstGroup(_ariaLabelRegExp, body)?.replaceFirst(RegExp(r'\s+cover$'), '') ??
          _firstGroup(_strongTextRegExp, body) ??
          '';
      final String title = unescapeHtml(rawTitle).trim();

      galleries.add(
        Gallery(
          galleryUrl: galleryUrlOf(id),
          title: title.isEmpty ? '8muses #$id' : title,
          category: '8muses',
          cover: GalleryImage(url: coverUrl(id)),
          pageCount: pages[id],
          rating: 0,
          hasRated: false,
          publishTime: _nowString(),
          isExpunged: false,
          tags: LinkedHashMap<String, List<GalleryTag>>(),
          externalTags: genres[id] ?? const <String>[],
        ),
      );
    }

    return galleries;
  }

  /// Genres of every gallery on a listing/tag/artist page.
  ///
  /// Search result pages do not include them (the field is an empty array), so
  /// tag filtering is only possible on tag/artist/listing pages.
  static Map<int, List<String>> parseGenresMap(String html) {
    final Map<int, List<String>> result = <int, List<String>>{};
    for (final Match match in _rscIdRegExp.allMatches(html)) {
      final int? id = int.tryParse(match.group(1) ?? '');
      if (id == null || result.containsKey(id)) {
        continue;
      }

      final int end = match.start + 1600;
      final String segment = html.substring(match.end, end < html.length ? end : html.length);
      final Match? genresMatch = RegExp(r'\\"genres\\":\[(.*?)\]').firstMatch(segment) ?? RegExp(r'"genres":\[(.*?)\]').firstMatch(segment);
      if (genresMatch == null) {
        continue;
      }

      final String raw = genresMatch.group(1) ?? '';
      final List<String> genres = RegExp(r'\\?"([^"\\]+)\\?"')
          .allMatches(raw)
          .map((Match m) => unescapeHtml((m.group(1) ?? '').replaceAll(r'\"', '"')).trim())
          .where((String e) => e.isNotEmpty)
          .toList();
      result[id] = genres;
    }
    return result;
  }

  /// Tag directory (`/genres`) and artist directory (`/artists`) are both grids
  /// of `.directory-card` links with a count in `<small>`.
  static List<EightMusesTag> _parseDirectory(String html, String segment) {
    final List<EightMusesTag> tags = <EightMusesTag>[];
    final Set<String> seen = <String>{};

    final RegExp cardRegExp = RegExp(
      '<a class="directory-card"[^>]*?title="([^"]*)"[^>]*?href="/$segment/([^"]*)"[^>]*>([\\s\\S]*?)</a>',
    );
    for (final Match match in cardRegExp.allMatches(html)) {
      final String label = unescapeHtml(match.group(1) ?? '').trim();
      final String slug = (match.group(2) ?? '').trim();
      if (slug.isEmpty || !seen.add(slug)) {
        continue;
      }

      final Match? countMatch = RegExp(r'<small>([\d.,\s]+)').firstMatch(match.group(3) ?? '');
      final int count = countMatch == null ? 0 : int.tryParse(countMatch.group(1)!.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

      tags.add(EightMusesTag(slug: slug, label: label.isEmpty ? slug : label, count: count));
    }

    tags.sort((EightMusesTag a, EightMusesTag b) => b.count.compareTo(a.count));
    return tags;
  }

  /// Tag directory (`/genres`): 120 tags with their gallery counts.
  static List<EightMusesTag> parseTags(String html) => _parseDirectory(html, 'tag');

  /// Artist directory (`/artists`): featured artists with their gallery counts.
  static List<EightMusesTag> parseArtists(String html) => _parseDirectory(html, 'artist');

  /// Map of gallery id -> page count, taken from the RSC payload of a listing.
  ///
  /// Best effort: the payload is a stream of objects, so `pages` is searched
  /// only in a bounded window after each `id`.
  static Map<int, int> parsePagesMap(String html) {
    final Map<int, int> result = <int, int>{};
    for (final Match match in _rscIdRegExp.allMatches(html)) {
      final int? id = int.tryParse(match.group(1) ?? '');
      if (id == null || result.containsKey(id)) {
        continue;
      }

      final int end = match.start + 1600;
      final String segment = html.substring(match.end, end < html.length ? end : html.length);
      final Match? pagesMatch = RegExp(r'\\"pages\\":(\d+)').firstMatch(segment);
      if (pagesMatch != null) {
        result[id] = int.parse(pagesMatch.group(1)!);
      }
    }
    return result;
  }

  /// Tags of a gallery page, from the `.detail-genre-row` links.
  ///
  /// The row is the only place where the page exposes the real tags with both
  /// slug and label (`<a href="/tag/big-breasts">Big Breasts</a>`); the JSON-LD
  /// block only carries the content type ("Image Set"/"Manga").
  static List<EightMusesTag> parseDetailTags(String html) {
    final Match? row = RegExp(r'<div class="detail-genre-row">([\s\S]*?)</div>').firstMatch(html);
    if (row == null) {
      return const <EightMusesTag>[];
    }

    final List<EightMusesTag> tags = <EightMusesTag>[];
    final Set<String> seen = <String>{};
    for (final Match match in RegExp(r'href="/tag/([^"]+)"[^>]*>([^<]*)</a>').allMatches(row.group(1) ?? '')) {
      final String slug = (match.group(1) ?? '').trim();
      if (slug.isEmpty || !seen.add(slug)) {
        continue;
      }

      final String label = unescapeHtml(match.group(2) ?? '').trim();
      tags.add(EightMusesTag(slug: slug, label: label.isEmpty ? slug : label));
    }

    return tags;
  }

  /// Metadata of a gallery page, or null when the page is not a gallery page.
  static EightMusesDetail? parseDetail(String html, int id) {
    final Map<String, dynamic>? creativeWork = _extractCreativeWork(html);

    String title = _stringValue(creativeWork?['name']) ?? _stringValue(creativeWork?['headline']) ?? '';
    String author = '';
    String description = _stringValue(creativeWork?['description']) ?? '';
    final List<EightMusesTag> tags = parseDetailTags(html);
    int? pageCount;

    final dynamic authorValue = creativeWork?['author'];
    if (authorValue is Map) {
      author = _stringValue(authorValue['name']) ?? '';
    } else if (authorValue is String) {
      author = authorValue;
    }

    final dynamic pagesValue = creativeWork?['numberOfPages'];
    if (pagesValue is num) {
      pageCount = pagesValue.toInt();
    }

    /// RSC fallback for anything the JSON-LD block does not expose.
    pageCount ??= _rscInt(html, id, 'pages');
    if (title.isEmpty) {
      title = unescapeHtml(_rscString(html, id, 'title') ?? '').trim();
    }
    if (author.isEmpty) {
      author = unescapeHtml(_rscString(html, id, 'author') ?? '').trim();
    }
    if (description.isEmpty) {
      description = unescapeHtml(_rscString(html, id, 'description') ?? '').trim();
    }

    final double? rating = _rscDouble(html, id, 'rating');
    final String? updated = _rscString(html, id, 'updated');

    if (pageCount == null || pageCount <= 0) {
      return null;
    }

    return EightMusesDetail(
      id: id,
      title: title.isEmpty ? '8muses #$id' : title,
      author: author,
      pageCount: pageCount,
      rating: rating ?? 0,
      description: description,
      tags: tags,
      publishTime: _relativeTime2DateString(updated) ?? _nowString(),
    );
  }

  /// Minimal [Gallery] for an external gallery opened from a url
  /// (clipboard / share intent / command line). The details page replaces the
  /// placeholder title with the real one after loading it.
  static Gallery galleryFromUrl(GalleryUrl galleryUrl) {
    final int id = galleryUrl.externalId!;
    return Gallery(
      galleryUrl: galleryUrl,
      title: '8muses #$id',
      category: '8muses',
      cover: GalleryImage(url: coverUrl(id)),
      rating: 0,
      hasRated: false,
      publishTime: _nowString(),
      isExpunged: false,
      tags: LinkedHashMap<String, List<GalleryTag>>(),
    );
  }

  static Map<String, dynamic>? _extractCreativeWork(String html) {
    for (final Match match in _ldJsonRegExp.allMatches(html)) {
      final String raw = (match.group(1) ?? '').trim();
      if (raw.isEmpty) {
        continue;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        continue;
      }

      final Map<String, dynamic>? found = _findCreativeWork(decoded);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _findCreativeWork(dynamic node) {
    if (node is List) {
      for (final dynamic item in node) {
        final Map<String, dynamic>? found = _findCreativeWork(item);
        if (found != null) {
          return found;
        }
      }
      return null;
    }

    if (node is! Map) {
      return null;
    }

    final Map<String, dynamic> map = node.map((dynamic key, dynamic value) => MapEntry(key.toString(), value));
    if (map['@type'] == 'CreativeWork') {
      return map;
    }

    final dynamic graph = map['@graph'];
    if (graph != null) {
      return _findCreativeWork(graph);
    }

    return null;
  }

  /// Position of the RSC object of [id], or -1.
  static int _rscObjectStart(String html, int id) {
    final Match? match = RegExp(r'\\"id\\":\\"' + id.toString() + r'\\"').firstMatch(html);
    return match?.start ?? -1;
  }

  static String? _rscString(String html, int id, String key) {
    final String? segment = _rscSegment(html, id);
    if (segment == null) {
      return null;
    }

    final Match? match = RegExp(r'\\"' + key + r'\\":\\"((?:[^"\\]|\\.)*?)\\"').firstMatch(segment);
    final String? value = match?.group(1);
    if (value == null) {
      return null;
    }

    return value.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');
  }

  static int? _rscInt(String html, int id, String key) {
    final String? segment = _rscSegment(html, id);
    if (segment == null) {
      return null;
    }

    final Match? match = RegExp(r'\\"' + key + r'\\":(\d+)').firstMatch(segment);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static double? _rscDouble(String html, int id, String key) {
    final String? segment = _rscSegment(html, id);
    if (segment == null) {
      return null;
    }

    final Match? match = RegExp(r'\\"' + key + r'\\":([\d.]+)').firstMatch(segment);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  static String? _rscSegment(String html, int id) {
    final int start = _rscObjectStart(html, id);
    if (start < 0) {
      return null;
    }

    final int end = start + 2000;
    return html.substring(start, end < html.length ? end : html.length);
  }

  /// Turns the site's "3d ago" / "2h ago" strings into `yyyy-MM-dd HH:mm`.
  static String? _relativeTime2DateString(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final Match? match = RegExp(r'^(\d+)\s*([smhdw])').firstMatch(value.trim());
    if (match == null) {
      return null;
    }

    final int amount = int.tryParse(match.group(1)!) ?? 0;
    final DateTime now = DateTime.now();
    final DateTime time = switch (match.group(2)) {
      's' => now.subtract(Duration(seconds: amount)),
      'm' => now.subtract(Duration(minutes: amount)),
      'h' => now.subtract(Duration(hours: amount)),
      'd' => now.subtract(Duration(days: amount)),
      'w' => now.subtract(Duration(days: amount * 7)),
      _ => now,
    };

    return DateFormat('yyyy-MM-dd HH:mm').format(time);
  }

  static String _nowString() => DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

  static String? _firstGroup(RegExp regExp, String source) {
    final Match? match = regExp.firstMatch(source);
    return match?.group(1);
  }

  static String? _stringValue(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  /// Decodes the handful of entities used in `title`/`aria-label` attributes.
  static String unescapeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }
}
