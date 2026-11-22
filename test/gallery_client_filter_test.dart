import 'dart:collection';

import 'package:acervo_hc/src/database/database.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:flutter_test/flutter_test.dart';

Gallery _makeGallery({
  required int gid,
  required String title,
  String category = 'Doujinshi',
  String? language,
  String? uploader,
  Map<String, List<String>> tags = const <String, List<String>>{},
}) {
  final LinkedHashMap<String, List<GalleryTag>> mappedTags = LinkedHashMap<String, List<GalleryTag>>();
  tags.forEach((String ns, List<String> keys) {
    mappedTags[ns] = keys.map((String k) => GalleryTag(tagData: TagData(namespace: ns, key: k))).toList();
  });
  return Gallery(
    galleryUrl: GalleryUrl(isEH: true, gid: gid, token: '0123456789'),
    title: title,
    category: category,
    cover: GalleryImage(url: 'https://example.com/$gid.jpg'),
    pageCount: 24,
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
        category: 'Doujinshi',
        language: 'english',
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
        tags: <String, List<String>>{
          'male': <String>['yaoi'],
        },
      ),
      _makeGallery(
        gid: 3,
        title: '[Artist C] Western Comic',
        category: 'Western',
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
      expect(result.map((Gallery g) => g.gid).toList(), <int>[1, 3]);
    });

    test('supports space-separated keyword inclusions and -exclusions across title and tags', () {
      const GalleryClientFilter filter = GalleryClientFilter(keyword: 'full color -yaoi');
      final List<Gallery> result = filter.apply(sample);
      expect(result.map((Gallery g) => g.gid).toList(), <int>[1]);

      const GalleryClientFilter excludeOnly = GalleryClientFilter(keyword: '-yaoi -western');
      expect(excludeOnly.apply(sample).map((Gallery g) => g.gid).toList(), <int>[1]);
    });
  });
}
