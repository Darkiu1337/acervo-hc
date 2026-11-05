import 'gallery_image.dart';
import 'gallery_thumbnail.dart';

import '../setting/read_setting.dart';

enum ReadMode { downloaded, online, archive, local }

class ReadPageInfo {
  ReadMode mode;

  /// null for local gallery
  int? gid;

  /// null for local gallery
  String? token;

  String galleryTitle;

  String? galleryUrl;

  int initialIndex;

  int currentImageIndex;

  int pageCount;

  /// used for archive
  bool isOriginal;

  String readProgressRecordStorageKey;

  /// used for archive&local
  List<GalleryImage>? images;

  /// Pre-resolved thumbnails of the external source (Xlecx). When set together
  /// with [images] in [ReadMode.online], the reader never parses E-H pages.
  List<GalleryThumbnail>? thumbnails;

  ReadDirection? readDirection;

  ReadPageInfo({
    required this.mode,
    this.gid,
    this.token,
    required this.galleryTitle,
    this.galleryUrl,
    required this.initialIndex,
    required this.pageCount,
    this.isOriginal = false,
    required this.readProgressRecordStorageKey,
    this.images,
    this.thumbnails,
    this.readDirection,
  }) : currentImageIndex = initialIndex;
}
