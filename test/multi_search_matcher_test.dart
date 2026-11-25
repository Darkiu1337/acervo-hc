import 'dart:collection';

import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/utils/multi_search_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

Gallery _make({
  required GallerySource source,
  required int id,
  required String title,
  String? altTitle,
  int pageCount = 24,
  String? uploader,
}) {
  final GalleryUrl url = source == GallerySource.eh
      ? GalleryUrl(isEH: true, gid: id, token: '0123456789')
      : source == GallerySource.xlecx
          ? GalleryUrl.xlecxGalleryUrl(id)
          : GalleryUrl.nhentaiGalleryUrl(id);

  return Gallery(
    galleryUrl: url,
    title: title,
    altTitle: altTitle,
    category: 'Doujinshi',
    cover: GalleryImage(url: 'https://example.com/$id.jpg'),
    pageCount: pageCount,
    rating: 0,
    hasRated: false,
    uploader: uploader,
    publishTime: '2026-01-01 12:00',
    isExpunged: false,
    tags: LinkedHashMap<String, List<GalleryTag>>(),
  );
}

void main() {
  group('MultiSearchMatcher', () {
    test('detects cross-provider matches across E-Hentai, Xlecx, and nhentai without false-matching sequels', () {
      final Gallery eh = _make(
        source: GallerySource.eh,
        id: 10001,
        title: '[Artist Alpha] Midnight Adventure in Wonderland [English]',
        pageCount: 32,
      );
      final Gallery nh = _make(
        source: GallerySource.nhentai,
        id: 550001,
        title: '[Artist Alpha] Midnight Adventure in Wonderland [English]',
        pageCount: 32,
      );
      final Gallery xlecxSequel = _make(
        source: GallerySource.xlecx,
        id: 77001,
        title: '[Artist Alpha] Midnight Adventure in Wonderland 2',
        pageCount: 32,
      );

      final Map<int, Set<GallerySource>> matches = MultiSearchMatcher.findCrossProviderMatches(
        <GallerySource, List<Gallery>>{
          GallerySource.eh: <Gallery>[eh],
          GallerySource.nhentai: <Gallery>[nh],
          GallerySource.xlecx: <Gallery>[xlecxSequel],
        },
      );

      expect(matches[eh.gid], <GallerySource>{GallerySource.nhentai});
      expect(matches[nh.gid], <GallerySource>{GallerySource.eh});
      expect(matches[xlecxSequel.gid], isNull);
    });

    test('interleaves provider results round-robin', () {
      final Gallery e1 = _make(source: GallerySource.eh, id: 1, title: 'E1');
      final Gallery e2 = _make(source: GallerySource.eh, id: 2, title: 'E2');
      final Gallery x1 = _make(source: GallerySource.xlecx, id: 10, title: 'X1');
      final Gallery n1 = _make(source: GallerySource.nhentai, id: 20, title: 'N1');
      final Gallery n2 = _make(source: GallerySource.nhentai, id: 21, title: 'N2');

      final List<Gallery> combined = MultiSearchMatcher.interleaveResults(<GallerySource, List<Gallery>>{
        GallerySource.eh: <Gallery>[e1, e2],
        GallerySource.xlecx: <Gallery>[x1],
        GallerySource.nhentai: <Gallery>[n1, n2],
      });

      expect(combined.map((g) => g.title).toList(), <String>['E1', 'X1', 'N1', 'E2', 'N2']);
    });
  });
}
