import 'package:acervo_hc/src/model/gallery_url.dart';

class GalleryHistoryModel {
  GalleryUrl galleryUrl;
  String title;
  String category;
  String coverUrl;
  int pageCount;
  double rating;
  String language;
  String uploader;
  String publishTime;
  bool isExpunged;
  List<String> tags;

  /// Optional alternate title (e.g. English/Romaji when Japanese title is
  /// preferred, or vice-versa) so cross-provider matching sees both forms.
  String? altTitle;

  /// Optional 128-bit perceptual gradient hash (32 hex chars) of [coverUrl]
  /// used to match the same gallery across E-Hentai/ExHentai and Xlecx even
  /// when titles differ completely.
  String? coverHash;

  GalleryHistoryModel({
    required this.galleryUrl,
    required this.title,
    required this.category,
    required this.coverUrl,
    required this.pageCount,
    required this.rating,
    required this.language,
    required this.uploader,
    required this.publishTime,
    required this.isExpunged,
    required this.tags,
    this.altTitle,
    this.coverHash,
  });

  Map<String, dynamic> toJson() {
    return {
      "galleryUrl": this.galleryUrl.url,
      "title": this.title,
      "category": this.category,
      "coverUrl": this.coverUrl,
      "pageCount": this.pageCount,
      "rating": this.rating,
      "language": this.language,
      "uploader": this.uploader,
      "publishTime": this.publishTime,
      "isExpunged": this.isExpunged,
      "tags": this.tags,
      if (this.altTitle != null && this.altTitle!.isNotEmpty) "altTitle": this.altTitle,
      if (this.coverHash != null && this.coverHash!.isNotEmpty) "coverHash": this.coverHash,
    };
  }

  factory GalleryHistoryModel.fromJson(Map<String, dynamic> json) {
    return GalleryHistoryModel(
      galleryUrl: GalleryUrl.parse(json["galleryUrl"]),
      title: json["title"],
      category: json["category"],
      coverUrl: json["coverUrl"],
      pageCount: json["pageCount"],
      rating: json["rating"],
      language: json["language"],
      uploader: json["uploader"],
      publishTime: json["publishTime"],
      isExpunged: json["isExpunged"],
      tags: json["tags"].cast<String>(),
      altTitle: json["altTitle"] as String?,
      coverHash: json["coverHash"] as String?,
    );
  }

  @override
  String toString() {
    return 'GalleryHistoryModel{galleryUrl: $galleryUrl, title: $title, category: $category, coverUrl: $coverUrl, pageCount: $pageCount, rating: $rating, language: $language, uploader: $uploader, publishTime: $publishTime, isExpunged: $isExpunged, tags: $tags, altTitle: $altTitle, coverHash: $coverHash}';
  }
}
