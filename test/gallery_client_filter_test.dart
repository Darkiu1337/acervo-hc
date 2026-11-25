import 'dart:collection';

import 'package:acervo_hc/src/database/database.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:flutter_test/flutter_test.dart';

Gallery _makeGallery({
  required int gid,
  required String title,
  String? altTitle,
  String category = 'Doujinshi',
  String? language,
  String? uploader,
  int pageCount = 24,
  GallerySource source = GallerySource.eh,
  Map<String, List<String>> tags = const <String, List<String>>{},
}) {
  final LinkedHashMap<String, List<GalleryTag>> mappedTags = LinkedHashMap<String, List<GalleryTag>>();
  tags.forEach((String ns, List<String> keys) {
    mappedTags[ns] = keys.map((String k) => GalleryTag(tagData: TagData(namespace: ns, key: k))).toList();
  });
  final GalleryUrl url = source == GallerySource.eh
      ? GalleryUrl(isEH: true, gid: gid, token: '0123456789')
      : source == GallerySource.xlecx
          ? GalleryUrl.xlecxGalleryUrl(gid)
          : GalleryUrl.nhentaiGalleryUrl(gid);
  return Gallery(
    galleryUrl: url,
    title: title,
    altTitle: altTitle,
    category: category,
    cover: GalleryImage(url: 'https://example.com/$gid.jpg'),
    pageCount: pageCount,
    rating: 4.5,
    hasRated: false,
    language: language,
    uploader: uploader,
    publishTime: '2026-01-01 12:00',
    isExpunged: false,
    tags: mappedTags,
  );
}

void main() {
  group('GalleryClientFilter', () {
    final List<Gallery> sample = <Gallery>[
      _makeGallery(
        gid: 1,
        title: '[Artist A] Full Color Fantasy [English]',
        altTitle: 'Fantasie Alt',
        category: 'Doujinshi',
        language: 'english',
        pageCount: 40,
        source: GallerySource.eh,
        tags: <String, List<String>>{
          'other': <String>['full color'],
          'female': <String>['elf'],
        },
      ),
      _makeGallery(
        gid: 2,
        title: '[Artist B] Monochrome Story [Portuguese]',
        category: 'Manga',
        language: 'portuguese',
        pageCount: 15,
        source: GallerySource.xlecx,
        tags: <String, List<String>>{
          'male': <String>['yaoi'],
        },
      ),
      _makeGallery(
        gid: 3,
        title: '[Artist C] Western Comic',
        category: 'Western',
        pageCount: 80,
        source: GallerySource.nhentai,
        tags: <String, List<String>>{
          'language': <String>['english'],
        },
      ),
    ];

    test('inactive filter returns all galleries', () {
      const GalleryClientFilter filter = GalleryClientFilter();
      expect(filter.isActive, isFalse);
      expect(filter.apply(sample).length, 3);
    });

    test('filters out disabled categories case-insensitively', () {
      const GalleryClientFilter filter = GalleryClientFilter(disabledCategories: <String>{'Western', 'Manga'});
      final List<Gallery> result = filter.apply(sample);
      expect(result.map((Gallery g) => g.gid).toList(), <int>[1]);
    });

    test('filters by language field or language tag', () {
      const GalleryClientFilter filter = GalleryClientFilter(language: 'english');
      final List<Gallery> result = filter.apply(sample);
      expect(result.map((Gallery g) => g.galleryUrl.source).toList(), <GallerySource>[GallerySource.eh, GallerySource.nhentai]);
    });

    test('supports space-separated keyword inclusions and -exclusions across title, altTitle, and tags', () {
      const GalleryClientFilter filter = GalleryClientFilter(keyword: 'full color -yaoi');
      final List<Gallery> result = filter.apply(sample);
      expect(result.map((Gallery g) => g.gid).toList(), <int>[1]);

      const GalleryClientFilter altMatch = GalleryClientFilter(keyword: 'fantasie');
      expect(altMatch.apply(sample).map((Gallery g) => g.gid).toList(), <int>[1]);

      const GalleryClientFilter excludeOnly = GalleryClientFilter(keyword: '-yaoi -western');
      expect(excludeOnly.apply(sample).map((Gallery g) => g.gid).toList(), <int>[1]);
    });

    test('filters by provider source', () {
      const GalleryClientFilter nhOnly = GalleryClientFilter(sources: <GallerySource>{GallerySource.nhentai});
      expect(nhOnly.apply(sample).map((Gallery g) => g.galleryUrl.source).toList(), <GallerySource>[GallerySource.nhentai]);

      const GalleryClientFilter externalOnly =
          GalleryClientFilter(sources: <GallerySource>{GallerySource.xlecx, GallerySource.nhentai});
      expect(externalOnly.apply(sample).length, 2);
    });

    test('sorts galleries by title and page count', () {
      const GalleryClientFilter byPagesDesc = GalleryClientFilter(sortOrder: GallerySortOption.pagesDesc);
      expect(byPagesDesc.apply(sample).map((Gallery g) => g.pageCount).toList(), <int?>[80, 40, 15]);

      const GalleryClientFilter byPagesAsc = GalleryClientFilter(sortOrder: GallerySortOption.pagesAsc);
      expect(byPagesAsc.apply(sample).map((Gallery g) => g.pageCount).toList(), <int?>[15, 40, 80]);

      const GalleryClientFilter byTitleDesc = GalleryClientFilter(sortOrder: GallerySortOption.titleDesc);
      expect(byTitleDesc.apply(sample).first.title, '[Artist C] Western Comic');
    });
  });
}
