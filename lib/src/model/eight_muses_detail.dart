import 'package:acervo_hc/src/model/eight_muses_search.dart';

/// Metadata of an 8muses gallery, as far as the site exposes it.
class EightMusesDetail {
  final int id;
  final String title;
  final String author;
  final int pageCount;
  final double rating;
  final String description;

  /// Real tags of the gallery, parsed from the detail page's genre row.
  /// Empty when the gallery has no tags.
  final List<EightMusesTag> tags;

  /// `yyyy-MM-dd HH:mm`, derived from the site's relative "updated" field.
  final String publishTime;

  const EightMusesDetail({
    required this.id,
    required this.title,
    required this.author,
    required this.pageCount,
    required this.rating,
    required this.description,
    required this.tags,
    required this.publishTime,
  });

  List<String> get tagLabels => tags.map((EightMusesTag tag) => tag.label).toList();

  @override
  String toString() {
    return 'EightMusesDetail{id: $id, title: $title, author: $author, pageCount: $pageCount, rating: $rating, tags: $tags}';
  }
}
