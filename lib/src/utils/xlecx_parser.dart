import 'dart:collection';

import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/model/xlecx_detail.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:intl/intl.dart';

/// Parsers for https://xlecx.one (a DataLife Engine site).
///
/// Everything is server-rendered HTML:
///
/// - listing/search pages: `a.thumb--model` cards with the post url, the title,
///   the cover and a label that is either `12 img` / `92 pages` (image gallery)
///   or `04:18` (video — those are dropped);
/// - `/<id>-<slug>.html` post: `h1`, a `page__subinfo` block with
///   Artist/Parody/Group/Tags rows and the page list;
/// - `/tags/` directory with ~1000 tags and their counts.
///
/// The page list comes in two shapes, both handled by [_galleryRegExp]:
///
/// - new posts: `ul.xfieldimagegallery > li > a[href=full] > img[data-src=thumb]`;
/// - old posts: `div.page__text > a.highslide[href=full] > img[data-src=thumb]`.
///
/// Filtering is a URL scheme (`/f/<key>=<value>/.../sort=<key>/order=<dir>/`),
/// which is what [filterPath] builds.
class XlecxParser {
  static const String baseUrl = 'https://xlecx.one';

  static const String categoryLabel = 'Xlecx';

  /// Canonical post url. The slug is irrelevant to the site, and a wrong one
  /// 301s to the real slug, so the id alone is enough.
  static String galleryPageUrl(int id) => '$baseUrl/$id-x.html';

  static GalleryUrl galleryUrlOf(int id) => GalleryUrl.xlecxGalleryUrl(id);

  static final RegExp _cardRegExp = RegExp(r'<a class="[^"]*thumb--model[^"]*" href="([^"]+)">([\s\S]*?)</a>');
  static final RegExp _titleRegExp = RegExp(r'<h3[^>]*>([\s\S]*?)</h3>');
  static final RegExp _coverRegExp = RegExp(r'<img[^>]*\bsrc="([^"]+)"');
  static final RegExp _labelRegExp = RegExp(r'thumb__label--time[^>]*>([^<]*)<');

  static final RegExp _h1RegExp = RegExp(r'<h1>([\s\S]*?)</h1>');

  /// Full size image anchored to its `/thumbs/` preview, in page order.
  static final RegExp _galleryRegExp = RegExp(r'<a\s+href="(https://xlecx\.one/uploads/posts/[^"]+)"[^>]*>\s*<img([^>]*)>');
  static final RegExp _thumbSrcRegExp = RegExp(r'data-src="([^"]+)"');

  static final RegExp _pagesLabelRegExp = RegExp(r'(\d+)\s*(?:img|pages?)', caseSensitive: false);
  static final RegExp _durationLabelRegExp = RegExp(r'^\d{1,2}:\d{2}$');

  static final RegExp _artistRowRegExp = RegExp(r'<div>Artist:</div>([\s\S]*?)</div>');
  static final RegExp _parodyRowRegExp = RegExp(r'<div>Parody:</div>([\s\S]*?)</div>');
  static final RegExp _groupRowRegExp = RegExp(r'<div>Group:</div>([\s\S]*?)</div>');
  static final RegExp _tagsRowRegExp = RegExp(r'<div>Tags:</div>([\s\S]*?)</div>');

  /// `MY TITLE | Today, 17:10 | Manga / Anime Parody / Furry`
  static final RegExp _descriptionRegExp = RegExp(r'data-description=(["\x27])([\s\S]*?)\1');
  static final RegExp _descriptionDateRegExp = RegExp(r'\|\s*([^|]*?,\s*\d{1,2}:\d{2})\s*\|');

  /// Gallery cards of a listing/search page, in page order. Video posts are
  /// dropped: they have no images and the reader cannot open them.
  static List<Gallery> parseGalleryList(String html) {
    final List<Gallery> galleries = <Gallery>[];
    final Set<int> seen = <int>{};

    for (final Match match in _cardRegExp.allMatches(html)) {
      final String href = match.group(1) ?? '';
      final int? id = idFromUrl(href);
      if (id == null || !seen.add(id)) {
        continue;
      }

      final String body = match.group(2) ?? '';
      final String title = unescapeHtml(stripTags(_firstGroup(_titleRegExp, body) ?? '')).trim();
      final String? cover = _firstGroup(_coverRegExp, body);
      final String label = unescapeHtml(_firstGroup(_labelRegExp, body) ?? '').trim();
      final int? pageCount = _parsePageCount(label);

      if (pageCount == null) {
        continue;
      }

      galleries.add(
        Gallery(
          galleryUrl: galleryUrlOf(id),
          title: title.isEmpty ? 'Xlecx #$id' : title,
          category: categoryLabel,
          cover: GalleryImage(url: encodeUrl(absoluteUrl(cover ?? ''))),
          pageCount: pageCount,
          rating: 0,
          hasRated: false,
          publishTime: nowString(),
          isExpunged: false,
          tags: LinkedHashMap<String, List<GalleryTag>>(),
          externalTags: const <String>[],
        ),
      );
    }

    return galleries;
  }

  /// True while the site still shows a "Next" link, i.e. there are more pages.
  static bool parseHasNextPage(String html) => RegExp(r'>\s*Next\s*</a>').hasMatch(html);

  /// Metadata of a post, or null when it has no page images (video posts).
  static XlecxDetail? parseDetail(String html, int id) {
    final List<String> pageUrls = <String>[];
    final List<String> thumbUrls = <String>[];
    final Set<String> seenPages = <String>{};

    for (final Match match in _galleryRegExp.allMatches(html)) {
      final String full = (match.group(1) ?? '').trim();
      if (full.isEmpty || !seenPages.add(full)) {
        continue;
      }

      final String? thumb = _thumbSrcRegExp.firstMatch(match.group(2) ?? '')?.group(1);
      pageUrls.add(encodeUrl(full));
      thumbUrls.add(thumb == null || thumb.trim().isEmpty ? encodeUrl(full) : encodeUrl(absoluteUrl(thumb.trim())));
    }

    if (pageUrls.isEmpty) {
      _collectInlineImages(html, pageUrls, thumbUrls, seenPages);
    }

    if (pageUrls.isEmpty) {
      return null;
    }

    final String title = unescapeHtml(stripTags(_firstGroup(_h1RegExp, html) ?? '')).trim();
    final String? description = _description(html);

    return XlecxDetail(
      id: id,
      title: title.isEmpty ? 'Xlecx #$id' : title,
      pageCount: pageUrls.length,
      pageUrls: pageUrls,
      thumbUrls: thumbUrls,
      artists: _parseXfsearchRow(html, _artistRowRegExp, XlecxTagKind.artist, 'artist'),
      parodies: _parseXfsearchRow(html, _parodyRowRegExp, XlecxTagKind.parody, 'parody'),
      groups: _parseXfsearchRow(html, _groupRowRegExp, XlecxTagKind.group, 'group'),
      tags: _parseTagsRow(html),
      categories: _parseCategories(description),
      publishTime: _parsePublishTime(description) ?? nowString(),
    );
  }

  /// Some older posts carry no anchors: the page list is a run of bare `<img>`
  /// tags inside the "Thumb"/"Full size" tabs (first one with `src`, the rest
  /// lazy `data-src`), already pointing at the full size file.
  static void _collectInlineImages(
    String html,
    List<String> pageUrls,
    List<String> thumbUrls,
    Set<String> seenPages,
  ) {
    for (final String id in <String>['content-1', 'content-2']) {
      final String section = _tabContent(html, id);
      if (section.isEmpty) {
        continue;
      }

      for (final Match match in RegExp(r'<img([^>]*)>', caseSensitive: false).allMatches(section)) {
        final String attrs = match.group(1) ?? '';
        final String? raw = _attribute(attrs, 'data-src') ?? _attribute(attrs, 'src');
        if (raw == null || !raw.contains('/uploads/posts/')) {
          continue;
        }

        final String full = _upgradeThumbnail(absoluteUrl(raw.trim()));
        if (!seenPages.add(full)) {
          continue;
        }

        pageUrls.add(encodeUrl(full));
        thumbUrls.add(encodeUrl(full));
      }

      if (pageUrls.isNotEmpty) {
        return;
      }
    }
  }

  /// Content of a tab (`#content-1` / `#content-2`), bounded by the next tab or
  /// the end of the article.
  static String _tabContent(String html, String id) {
    final int start = html.indexOf('id="$id"');
    if (start < 0) {
      return '';
    }

    int end = html.indexOf('</article>', start);
    if (id == 'content-1') {
      final int nextTab = html.indexOf('id="content-2"', start);
      if (nextTab > start && (end < 0 || nextTab < end)) {
        end = nextTab;
      }
    }

    return html.substring(start, end < 0 ? html.length : end);
  }

  static String? _attribute(String attrs, String name) {
    final Match? match = RegExp(name + r'\s*=\s*(["\x27])(.*?)\1', caseSensitive: false).firstMatch(attrs);
    return match?.group(2);
  }

  /// `/uploads/posts/2026-11/thumbs/001.jpg` -> `/uploads/posts/2026-11/001.jpg`.
  static String _upgradeThumbnail(String url) {
    const String marker = '/thumbs/';
    final int index = url.indexOf(marker);
    if (index < 0) {
      return url;
    }
    return url.replaceRange(index, index + marker.length, '/');
  }

  /// The `/tags/` directory (one page, ~1000 tags) sorted by gallery count.
  static List<XlecxTag> parseTags(String html) {
    final List<XlecxTag> tags = <XlecxTag>[];
    final Set<String> seen = <String>{};

    final RegExp itemRegExp = RegExp(r'<a href="https://xlecx\.one/tags/([^"]+)/"[^>]*title="Publication found: (\d+)"[^>]*>([^<]*)</a>');
    for (final Match match in itemRegExp.allMatches(html)) {
      final String slug = decodeSlug(match.group(1) ?? '');
      if (slug.isEmpty || !seen.add(slug)) {
        continue;
      }

      final String label = unescapeHtml(match.group(3) ?? '').trim();
      tags.add(
        XlecxTag(
          slug: slug,
          label: label.isEmpty ? slug : label,
          count: int.tryParse(match.group(2) ?? '') ?? 0,
        ),
      );
    }

    tags.sort((XlecxTag a, XlecxTag b) => b.count.compareTo(a.count));
    return tags;
  }

  /// Builds the site's filter path, in its own canonical order (keys sorted,
  /// `sort`/`order` last) so the server does not answer with a 301.
  static String filterPath({
    XlecxCategory category = XlecxCategory.all,
    List<String> includeTags = const <String>[],
    List<String> excludeTags = const <String>[],
    String? artist,
    String? parody,
    String? group,
    XlecxSort sort = XlecxSort.newest,
    int page = 1,
  }) {
    final Map<String, String> parts = <String, String>{};

    if (excludeTags.isNotEmpty) {
      parts['!n.m.tags'] = excludeTags.map(Uri.encodeQueryComponent).join(',');
    }
    if (artist != null && artist.isNotEmpty) {
      parts['artist'] = Uri.encodeQueryComponent(artist);
    }
    if (category.id != null) {
      parts['cat'] = category.id.toString();
    }
    if (group != null && group.isNotEmpty) {
      parts['group'] = Uri.encodeQueryComponent(group);
    }
    if (includeTags.isNotEmpty) {
      parts['n.m.tags'] = includeTags.map(Uri.encodeQueryComponent).join(',');
    }
    if (parody != null && parody.isNotEmpty) {
      parts['parody'] = Uri.encodeQueryComponent(parody);
    }

    final List<String> keys = parts.keys.toList()..sort();
    final StringBuffer buffer = StringBuffer('/f/');
    for (final String key in keys) {
      buffer.write('$key=${parts[key]}/');
    }
    buffer.write('sort=${sort.apiValue}/order=${sort.order}/');
    if (page > 1) {
      buffer.write('page/$page/');
    }

    return buffer.toString();
  }

  /// [Gallery] placeholder for a post opened from clipboard/share/CLI. The
  /// details page replaces the title once the real post is loaded.
  static Gallery galleryFromUrl(GalleryUrl galleryUrl) {
    final int id = galleryUrl.externalId!;
    return Gallery(
      galleryUrl: galleryUrl,
      title: 'Xlecx #$id',
      category: categoryLabel,
      cover: GalleryImage(url: ''),
      rating: 0,
      hasRated: false,
      publishTime: nowString(),
      isExpunged: false,
      tags: LinkedHashMap<String, List<GalleryTag>>(),
    );
  }

  /// Post id of a `https://xlecx.one/<id>-<slug>.html` url.
  static int? idFromUrl(String url) {
    final Match? match = RegExp(r'xlecx\.one/(\d+)(?:-[^/?#]*)?\.html').firstMatch(url);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// The site's urls are relative on cards and absolute on posts.
  static String absoluteUrl(String url) {
    if (url.isEmpty || url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return url.startsWith('/') ? '$baseUrl$url' : '$baseUrl/$url';
  }

  /// Percent-encodes the path of an image url. Post slugs and some uploads
  /// carry literal spaces and apostrophes, which the HTTP client cannot send.
  static String encodeUrl(String url) => Uri.encodeFull(url.trim());

  /// `big%20ass` -> `big ass`.
  static String decodeSlug(String value) {
    try {
      return Uri.decodeComponent(value).trim();
    } catch (_) {
      return value.trim();
    }
  }

  static String stripTags(String value) => value.replaceAll(RegExp(r'<[^>]+>'), ' ');

  static String nowString() => DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

  static int? _parsePageCount(String label) {
    if (label.isEmpty || _durationLabelRegExp.hasMatch(label)) {
      return null;
    }
    final Match? match = _pagesLabelRegExp.firstMatch(label);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static String? _description(String html) {
    for (final Match match in _descriptionRegExp.allMatches(html)) {
      final String value = unescapeHtml(match.group(2) ?? '').trim();
      if (value.contains('|')) {
        return value;
      }
    }
    return null;
  }

  static List<XlecxCategory> _parseCategories(String? description) {
    if (description == null) {
      return const <XlecxCategory>[];
    }

    /// The categories are the last `|`-separated segment of the description.
    final int index = description.lastIndexOf('|');
    if (index < 0) {
      return const <XlecxCategory>[];
    }

    final List<XlecxCategory> result = <XlecxCategory>[];
    for (final String name in description.substring(index + 1).split('/')) {
      final XlecxCategory? category = XlecxCategory.fromLabel(name);
      if (category != null && !result.contains(category)) {
        result.add(category);
      }
    }
    return result;
  }

  /// Turns `Today, 17:10` / `Yesterday, 00:14` / `17-10-2017, 00:14` into
  /// `yyyy-MM-dd HH:mm`.
  static String? _parsePublishTime(String? description) {
    if (description == null) {
      return null;
    }

    final Match? match = _descriptionDateRegExp.firstMatch(description);
    if (match == null) {
      return null;
    }

    final String value = match.group(1)!.trim();
    final Match? timeMatch = RegExp(r'(\d{1,2}):(\d{2})$').firstMatch(value);
    if (timeMatch == null) {
      return null;
    }

    final int hour = int.tryParse(timeMatch.group(1)!) ?? 0;
    final int minute = int.tryParse(timeMatch.group(2)!) ?? 0;
    final String datePart = value.substring(0, value.length - timeMatch.group(0)!.length).replaceAll(',', '').trim().toLowerCase();

    DateTime? date;
    if (datePart.startsWith('today')) {
      date = DateTime.now();
    } else if (datePart.startsWith('yesterday')) {
      date = DateTime.now().subtract(const Duration(days: 1));
    } else {
      final Match? absolute = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$').firstMatch(datePart);
      if (absolute != null) {
        date = DateTime(
          int.parse(absolute.group(3)!),
          int.parse(absolute.group(2)!),
          int.parse(absolute.group(1)!),
        );
      }
    }

    if (date == null) {
      return null;
    }

    return DateFormat('yyyy-MM-dd HH:mm').format(DateTime(date.year, date.month, date.day, hour, minute));
  }

  static List<XlecxTag> _parseXfsearchRow(String html, RegExp rowRegExp, XlecxTagKind kind, String path) {
    final String? row = _firstGroup(rowRegExp, html);
    if (row == null) {
      return const <XlecxTag>[];
    }

    final RegExp linkRegExp = RegExp('href="https://xlecx\\.one/xfsearch/' + path + r'/([^"]+)/"[^>]*>([\s\S]*?)</a>');
    final List<XlecxTag> result = <XlecxTag>[];
    final Set<String> seen = <String>{};

    for (final Match match in linkRegExp.allMatches(row)) {
      final String slug = decodeSlug(match.group(1) ?? '');
      if (slug.isEmpty || !seen.add(slug)) {
        continue;
      }

      final String label = unescapeHtml(stripTags(match.group(2) ?? '')).trim();
      result.add(XlecxTag(slug: slug, label: label.isEmpty ? slug : label, kind: kind));
    }

    return result;
  }

  static List<XlecxTag> _parseTagsRow(String html) {
    final String? row = _firstGroup(_tagsRowRegExp, html);
    if (row == null) {
      return const <XlecxTag>[];
    }

    final List<XlecxTag> result = <XlecxTag>[];
    final Set<String> seen = <String>{};

    for (final Match match in RegExp(r'href="https://xlecx\.one/tags/([^"]+)/"[^>]*>([\s\S]*?)</a>').allMatches(row)) {
      final String slug = decodeSlug(match.group(1) ?? '');
      if (slug.isEmpty || !seen.add(slug)) {
        continue;
      }

      final String label = unescapeHtml(stripTags(match.group(2) ?? '')).trim();
      result.add(XlecxTag(slug: slug, label: label.isEmpty ? slug : label));
    }

    return result;
  }

  static String? _firstGroup(RegExp regExp, String source) {
    final Match? match = regExp.firstMatch(source);
    return match?.group(1);
  }

  /// Decodes the entities used by titles, category names and image urls.
  static String unescapeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }
}
