import 'dart:collection';

import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/model/nhentai_gallery.dart';
import 'package:acervo_hc/src/network/nhentai_request.dart';
import 'package:acervo_hc/src/utils/gallery_identity_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GallerySource & GalleryUrl for nhentai', () {
    test('gid ranges cleanly separate eh, nhentai, and xlecx', () {
      expect(sourceOfGid(4600000), GallerySource.eh);
      expect(sourceOfGid(nhentaiGid(699178)), GallerySource.nhentai);
      expect(sourceOfGid(xlecxGid(64748)), GallerySource.xlecx);
      expect(nhentaiGid(699178), lessThan(xlecxGidOffset));
    });

    test('parses and formats nhentai URLs', () {
      final GalleryUrl? parsed = GalleryUrl.tryParse('https://nhentai.net/g/699178/');
      expect(parsed, isNotNull);
      expect(parsed!.source, GallerySource.nhentai);
      expect(parsed.externalId, 699178);
      expect(parsed.gid, nhentaiGid(699178));
      expect(parsed.url, 'https://nhentai.net/g/699178/');
    });

    test('tryParseNHentaiCode handles raw codes, #codes, and full URLs', () {
      expect(tryParseNHentaiCode('699178'), 699178);
      expect(tryParseNHentaiCode('#699178'), 699178);
      expect(tryParseNHentaiCode('https://nhentai.net/g/699178/'), 699178);
      expect(tryParseNHentaiCode('bremerton bikini'), isNull);
      expect(tryParseNHentaiCode(''), isNull);
    });
  });

  group('nhentai API v2 parsing & CDN resolution', () {
    const NHentaiCdnConfig cdn = NHentaiCdnConfig(
      imageServers: <String>['https://i1.nhentai.net', 'https://i2.nhentai.net'],
      thumbServers: <String>['https://t1.nhentai.net', 'https://t2.nhentai.net'],
    );

    test('resolves exact API paths including double extensions deterministically', () {
      final String cover = cdn.resolveThumbUrl('galleries/4345864/cover.webp.webp', seed: 1);
      final String page = cdn.resolveImageUrl('galleries/4345864/1.webp', seed: 2);
      expect(cover, 'https://t2.nhentai.net/galleries/4345864/cover.webp.webp');
      expect(page, 'https://i1.nhentai.net/galleries/4345864/1.webp');
    });

    test('parses summary and preserves both English and Japanese titles on Gallery', () {
      final NHentaiGallerySummary summary = NHentaiGallerySummary.fromJson(
        <String, dynamic>{
          'id': 678021,
          'media_id': '4156166',
          'english_title': '[nanohana] Bremerton Bikini (Azur Lane) [Digital] [English]',
          'japanese_title': '[nanohana] ブレマートン ビキニ (アズールレーン)',
          'thumbnail': 'galleries/4156166/thumb.webp',
          'thumbnail_width': 250,
          'thumbnail_height': 354,
          'num_pages': 6,
          'num_favorites': 1661,
        },
        cdn,
      );

      final Gallery gallery = summary.toGallery();
      expect(gallery.galleryUrl.source, GallerySource.nhentai);
      expect(gallery.title, '[nanohana] Bremerton Bikini (Azur Lane) [Digital] [English]');
      expect(gallery.altTitle, '[nanohana] ブレマートン ビキニ (アズールレーン)');
      expect(gallery.pageCount, 6);
      expect(gallery.cover.url, contains('/galleries/4156166/thumb.webp'));
    });

    test('parses detail payload with tags and pages', () {
      final NHentaiGalleryDetail detail = NHentaiGalleryDetail.fromJson(
        <String, dynamic>{
          'id': 699178,
          'media_id': '4345864',
          'title': <String, dynamic>{
            'english': '[Ogan] Bremerton Bikini Lesson (Azur Lane)',
            'japanese': '[おーがん] 執務中にビキニで誘惑するブレマートン',
            'pretty': 'Bremerton Bikini Lesson',
          },
          'cover': <String, dynamic>{'path': 'galleries/4345864/cover.webp.webp', 'width': 350, 'height': 184},
          'thumbnail': <String, dynamic>{'path': 'galleries/4345864/thumb.webp', 'width': 250, 'height': 131},
          'upload_date': 1760000000,
          'num_pages': 2,
          'num_favorites': 42,
          'tags': <Map<String, dynamic>>[
            <String, dynamic>{'id': 1, 'type': 'artist', 'name': 'ogan', 'slug': 'ogan', 'count': 10},
            <String, dynamic>{'id': 2, 'type': 'tag', 'name': 'big breasts', 'slug': 'big-breasts', 'count': 1000},
            <String, dynamic>{'id': 3, 'type': 'language', 'name': 'english', 'slug': 'english', 'count': 9999},
            <String, dynamic>{'id': 4, 'type': 'category', 'name': 'doujinshi', 'slug': 'doujinshi', 'count': 50000},
          ],
          'pages': <Map<String, dynamic>>[
            <String, dynamic>{
              'number': 1,
              'path': 'galleries/4345864/1.webp',
              'width': 1200,
              'height': 1800,
              'thumbnail': 'galleries/4345864/1t.webp',
            },
            <String, dynamic>{
              'number': 2,
              'path': 'galleries/4345864/2.webp',
              'width': 1280,
              'height': 1810,
              'thumbnail': 'galleries/4345864/2t.webp.webp',
            },
          ],
        },
        cdn,
      );

      expect(detail.pages.length, 2);
      expect(detail.artistNames, <String>['ogan']);
      expect(detail.categoryLabel, 'Doujinshi');
      expect(detail.languageLabel, 'english');
      expect(detail.tagsOfType('tag').first.searchToken, 'tag:"big breasts"');
      expect(detail.tagsOfType('artist').first.searchToken, 'artist:ogan');
    });

    test('buildEffectiveQuery builds wildcard search for popular sort', () {
      expect(
        NHentaiRequest.buildEffectiveQuery(query: '', language: NHentaiLanguage.all, sort: NHentaiSort.recent),
        '',
      );
      expect(
        NHentaiRequest.buildEffectiveQuery(query: '', language: NHentaiLanguage.all, sort: NHentaiSort.popularToday),
        '*',
      );
      expect(
        NHentaiRequest.buildEffectiveQuery(
          query: 'artist:ogan',
          language: NHentaiLanguage.english,
          sort: NHentaiSort.popularAll,
        ),
        'artist:ogan language:english',
      );
    });
  });

  group('3-way cross-provider Already Read matching with nhentai', () {
    test('matches ExHentai entry with Japanese title against nhentai summary via altTitle', () {
      final GalleryHistoryModel ehRead = GalleryHistoryModel(
        galleryUrl: const GalleryUrl(isEH: false, gid: 3123456, token: 'abcdef1234'),
        title: '[nanohana] ブレマートン ビキニ (アズールレーン)',
        category: 'Doujinshi',
        coverUrl: 'https://example.com/eh.jpg',
        pageCount: 6,
        rating: 4.8,
        language: 'english',
        uploader: 'uploader1',
        publishTime: '2026-01-01 00:00',
        isExpunged: false,
        tags: <String>['artist:nanohana'],
      );

      final Gallery nhCard = Gallery(
        galleryUrl: GalleryUrl.nhentaiGalleryUrl(678021),
        title: '[nanohana] Bremerton Bikini (Azur Lane) [Digital] [English]',
        altTitle: '[nanohana] ブレマートン ビキニ (アズールレーン)',
        category: 'nhentai',
        cover: GalleryImage(url: 'https://t1.nhentai.net/galleries/4156166/thumb.webp'),
        pageCount: 6,
        rating: 0,
        hasRated: false,
        publishTime: '',
        isExpunged: false,
        tags: LinkedHashMap<String, List<GalleryTag>>(),
      );

      final GalleryMatchResult? match = GalleryIdentityMatcher.match(
        GalleryIdentity.fromGallery(nhCard),
        GalleryIdentity.fromHistoryModel(ehRead),
      );
      expect(match, isNotNull);
    });

    test('matches Xlecx entry against nhentai entry with same title and artist', () {
      final GalleryHistoryModel xlecxRead = GalleryHistoryModel(
        galleryUrl: GalleryUrl.xlecxGalleryUrl(54321),
        title: 'Bremerton Bikini Adventure',
        category: 'Western',
        coverUrl: 'https://xlecx.one/cover.jpg',
        pageCount: 24,
        rating: 0,
        language: 'EN',
        uploader: 'nanohana',
        publishTime: '',
        isExpunged: false,
        tags: const <String>[],
      );

      final Gallery nhCard = Gallery(
        galleryUrl: GalleryUrl.nhentaiGalleryUrl(678022),
        title: '[nanohana] Bremerton Bikini Adventure [English]',
        category: 'nhentai',
        cover: GalleryImage(url: 'https://t1.nhentai.net/galleries/4156167/thumb.webp'),
        pageCount: 24,
        rating: 0,
        hasRated: false,
        publishTime: '',
        isExpunged: false,
        tags: LinkedHashMap<String, List<GalleryTag>>(),
      );

      final GalleryMatchResult? match = GalleryIdentityMatcher.match(
        GalleryIdentity.fromGallery(nhCard),
        GalleryIdentity.fromHistoryModel(xlecxRead),
      );
      expect(match, isNotNull);
    });

    test('does not false-match sequels across nhentai and E-Hentai', () {
      final GalleryHistoryModel ehPart1 = GalleryHistoryModel(
        galleryUrl: const GalleryUrl(isEH: false, gid: 3123457, token: 'abcdef1234'),
        title: '[nanohana] Bremerton Bikini 1 [English]',
        category: 'Doujinshi',
        coverUrl: 'https://example.com/eh1.jpg',
        pageCount: 24,
        rating: 4.8,
        language: 'english',
        uploader: 'uploader1',
        publishTime: '2026-01-01 00:00',
        isExpunged: false,
        tags: <String>['artist:nanohana'],
      );

      final Gallery nhPart2 = Gallery(
        galleryUrl: GalleryUrl.nhentaiGalleryUrl(678023),
        title: '[nanohana] Bremerton Bikini 2 [English]',
        category: 'nhentai',
        cover: GalleryImage(url: 'https://t1.nhentai.net/galleries/4156168/thumb.webp'),
        pageCount: 24,
        rating: 0,
        hasRated: false,
        publishTime: '',
        isExpunged: false,
        tags: LinkedHashMap<String, List<GalleryTag>>(),
      );

      final GalleryMatchResult? match = GalleryIdentityMatcher.match(
        GalleryIdentity.fromGallery(nhPart2),
        GalleryIdentity.fromHistoryModel(ehPart1),
      );
      expect(match, isNull);
    });

    test('matches same work in different languages within nhentai (English vs Japanese/Chinese)', () {
      final GalleryHistoryModel nhEnglish = GalleryHistoryModel(
        galleryUrl: GalleryUrl.nhentaiGalleryUrl(678021),
        title: '[nanohana] Bremerton Bikini (Azur Lane) [Digital] [English]',
        altTitle: '[nanohana] ブレマートン ビキニ (アズールレーン)',
        category: 'Doujinshi',
        coverUrl: 'https://t1.nhentai.net/galleries/4156166/thumb.webp',
        pageCount: 6,
        rating: 0,
        language: 'english',
        uploader: 'nanohana',
        publishTime: '2026-01-01 00:00',
        isExpunged: false,
        tags: <String>['artist:nanohana'],
      );

      final Gallery nhChinese = Gallery(
        galleryUrl: GalleryUrl.nhentaiGalleryUrl(678999),
        title: '[nanohana] ブレマートン ビキニ (アズールレーン) [中国翻訳]',
        altTitle: '[nanohana] Bremerton Bikini (Azur Lane) [Chinese] [個人漢化]',
        category: 'nhentai',
        cover: GalleryImage(url: 'https://t1.nhentai.net/galleries/4159999/thumb.webp'),
        pageCount: 6,
        rating: 0,
        hasRated: false,
        publishTime: '',
        isExpunged: false,
        tags: LinkedHashMap<String, List<GalleryTag>>(),
      );

      expect(
        GalleryIdentityMatcher.match(
          GalleryIdentity.fromGallery(nhChinese),
          GalleryIdentity.fromHistoryModel(nhEnglish),
        ),
        isNotNull,
      );
    });
  });
}
