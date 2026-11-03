import 'package:acervo_hc/src/model/xlecx_search.dart';

/// Metadata of a Xlecx gallery, as far as the site exposes it.
///
/// Both lists are already resolved and encoded: [pageUrls] are the full size
/// images (what the site's own lightbox opens) and [thumbUrls] the `/thumbs/`
/// variants used by the preview grid.
class XlecxDetail {
  final int id;
  final String title;
  final int pageCount;
  final List<String> pageUrls;
  final List<String> thumbUrls;
  final List<XlecxTag> artists;
  final List<XlecxTag> parodies;
  final List<XlecxTag> groups;
  final List<XlecxTag> tags;

  /// Sections of the site shown on the post (`Manga / Anime Parody / Furry`).
  final List<XlecxCategory> categories;

  /// `yyyy-MM-dd HH:mm`, derived from the post header.
  final String publishTime;

  const XlecxDetail({
    required this.id,
    required this.title,
    required this.pageCount,
    required this.pageUrls,
    required this.thumbUrls,
    required this.artists,
    required this.parodies,
    required this.groups,
    required this.tags,
    required this.categories,
    required this.publishTime,
  });

  List<String> get tagLabels => tags.map((XlecxTag tag) => tag.label).toList();

  List<String> get artistLabels => artists.map((XlecxTag tag) => tag.label).toList();

  String get coverUrl => thumbUrls.isEmpty ? '' : thumbUrls.first;

  @override
  String toString() {
    return 'XlecxDetail{id: $id, title: $title, pageCount: $pageCount, artists: $artists, tags: $tags}';
  }
}
