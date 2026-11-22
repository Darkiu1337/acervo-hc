import 'dart:collection';
import 'dart:typed_data';

import 'package:acervo_hc/src/database/database.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/utils/gallery_identity_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

Gallery _ehGallery({
  int gid = 100001,
  required String title,
  int? pageCount = 24,
  List<String> artists = const <String>[],
  List<String> groups = const <String>[],
}) {
  final LinkedHashMap<String, List<GalleryTag>> tags = LinkedHashMap<String, List<GalleryTag>>();
  if (artists.isNotEmpty) {
    tags['artist'] = artists.map((String a) => GalleryTag(tagData: TagData(namespace: 'artist', key: a))).toList();
  }
  if (groups.isNotEmpty) {
    tags['group'] = groups.map((String g) => GalleryTag(tagData: TagData(namespace: 'group', key: g))).toList();
  }
  return Gallery(
    galleryUrl: GalleryUrl(isEH: false, gid: gid, token: 'abcdef1234'),
    title: title,
    category: 'Doujinshi',
    cover: GalleryImage(url: 'https://ehgt.org/t/aa/bb/cover_250.jpg'),
    pageCount: pageCount,
    rating: 4.5,
    hasRated: false,
    publishTime: '2026-11-20 12:00',
    isExpunged: false,
    tags: tags,
  );
}

Gallery _xlecxGallery({
  int id = 65000,
  required String title,
  int? pageCount = 24,
  String? uploader,
}) {
  return Gallery(
    galleryUrl: GalleryUrl.xlecxGalleryUrl(id),
    title: title,
    category: 'Xlecx',
    cover: GalleryImage(url: 'https://xlecx.one/uploads/posts/2026-11/cover.webp'),
    pageCount: pageCount,
    rating: 0,
    hasRated: false,
    uploader: uploader,
    publishTime: '2026-11-20 12:00',
    isExpunged: false,
    tags: LinkedHashMap<String, List<GalleryTag>>(),
  );
}

/// Generates a deterministic 9x9 RGBA buffer with rich horizontal & vertical
/// gradients suitable for perceptual dHash testing.
Uint8List _syntheticCoverRgba({int seed = 1, int noise = 0}) {
  final Uint8List bytes = Uint8List(9 * 9 * 4);
  for (int y = 0; y < 9; y++) {
    for (int x = 0; x < 9; x++) {
      final int idx = (y * 9 + x) * 4;
      final int wave = ((x * 37 + y * 53 + seed * 97) ^ ((x + 3) * (y + 5) * (seed + 7))) & 0xFF;
      final int v = (wave + noise).clamp(0, 255);
      bytes[idx] = v;
      bytes[idx + 1] = v;
      bytes[idx + 2] = v;
      bytes[idx + 3] = 255;
    }
  }
  return bytes;
}

void main() {
  group('GalleryIdentityMatcher — cross-provider positive matches', () {
    test('matches exact distinctive title + page count across EH and Xlecx', () {
      final GalleryIdentity eh = GalleryIdentity.fromGallery(
        _ehGallery(title: '[Dross] Roxy and the Devil [complete]', pageCount: 9, artists: <String>['dross']),
      );
      final GalleryIdentity xlecx = GalleryIdentity.fromGallery(
        _xlecxGallery(title: 'Roxy and the Devil', pageCount: 9),
      );

      final GalleryMatchResult? result = GalleryIdentityMatcher.match(eh, xlecx);
      expect(result, isNotNull);
      expect(result!.reason, GalleryMatchReason.exactDistinctiveTitleAndPageCount);
    });

    test('matches bilingual titles with | and ー separators and off-by-1 page count', () {
      final GalleryIdentity eh = GalleryIdentity.fromGallery(
        _ehGallery(
          title:
              '[Popochichi (Yahiro Pochi)] Sono Bisque Doll wa H o Suru 9 ー  My Sexy Dress-Up Darling 9 (Sono Bisque Doll wa Koi o Suru) [English] [head empty] [Digital]',
          pageCount: 24,
          artists: <String>['yahiro pochi'],
          groups: <String>['popochichi'],
        ),
      );
      final GalleryIdentity xlecx = GalleryIdentity.fromGallery(
        _xlecxGallery(
          title: 'My Sexy Dress-Up Darling 9 | Sono Bisque Doll wa H o Suru 9',
          pageCount: 23,
        ),
      );

      expect(GalleryIdentityMatcher.match(eh, xlecx), isNotNull);
    });

    test('matches when chapter markers differ (Ep. 4 vs Ch. 4) and bracketed artist matches', () {
      final GalleryIdentity eh = GalleryIdentity.fromGallery(
        _ehGallery(
          title: '[FleshForge Studio] Thirty Doses Ch. 4 - The Bump [English]',
          pageCount: 23,
        ),
      );
      final GalleryIdentity xlecx = GalleryIdentity.fromGallery(
        _xlecxGallery(
          title: 'Thirty Doses Ep. 4 - The Bump [FleshForge Studio]',
          pageCount: 23,
        ),
      );

      final GalleryMatchResult? result = GalleryIdentityMatcher.match(eh, xlecx);
      expect(result, isNotNull);
      expect(result!.reason, GalleryMatchReason.exactTitleAndCreator);
    });

    test('matches EH history entry with Japanese primary title via altTitle', () {
      final GalleryHistoryModel ehHistory = GalleryHistoryModel(
        galleryUrl: const GalleryUrl(isEH: false, gid: 200001, token: '0123456789'),
        title: '[ポポチチ (八尋ぽち)] その着せ替え人形はHをする 9',
        altTitle: '[Popochichi (Yahiro Pochi)] Sono Bisque Doll wa H o Suru 9 (Sono Bisque Doll wa Koi o Suru) [English]',
        category: 'Doujinshi',
        coverUrl: 'https://ehgt.org/t/11/22/cover.jpg',
        pageCount: 24,
        rating: 4.8,
        language: 'english',
        uploader: 'uploader1',
        publishTime: '2026-11-20 12:00',
        isExpunged: false,
        tags: <String>['artist:yahiro pochi', 'group:popochichi'],
      );
      final GalleryIdentity ehId = GalleryIdentity.fromHistoryModel(ehHistory);
      final GalleryIdentity xlecxId = GalleryIdentity.fromGallery(
        _xlecxGallery(title: 'My Sexy Dress-Up Darling 9 | Sono Bisque Doll wa H o Suru 9', pageCount: 23),
      );

      expect(GalleryIdentityMatcher.match(ehId, xlecxId), isNotNull);
    });

    test('matches completely different titles via strong 128-bit perceptual cover hash + compatible pages', () {
      final CoverPerceptualHash? h1 = CoverPerceptualHash.fromRgba9x9(_syntheticCoverRgba(seed: 42, noise: 0));
      final CoverPerceptualHash? h2 = CoverPerceptualHash.fromRgba9x9(_syntheticCoverRgba(seed: 42, noise: 3));
      expect(h1, isNotNull);
      expect(h2, isNotNull);

      final GalleryIdentity eh = GalleryIdentity.fromGallery(
        _ehGallery(title: '[SomeArtist] Sensei Onegai Watashi o Basshite Kudasai [English]', pageCount: 26),
        coverHash: h1,
      );
      final GalleryIdentity xlecx = GalleryIdentity.fromGallery(
        _xlecxGallery(title: 'Sweet Discipline', pageCount: 26),
        coverHash: h2,
      );

      final GalleryMatchResult? result = GalleryIdentityMatcher.match(eh, xlecx);
      expect(result, isNotNull);
      expect(result!.reason, GalleryMatchReason.strongCoverHash);
    });
  });

  group('GalleryIdentityMatcher — multi-language same-provider deduplication', () {
    test('matches same work in different languages on the same provider', () {
      final GalleryIdentity jp = GalleryIdentity.fromGallery(
        _ehGallery(gid: 1, title: '[Dross] Roxy and the Devil', pageCount: 9),
      );
      final GalleryIdentity en = GalleryIdentity.fromGallery(
        _ehGallery(gid: 2, title: '[Dross] Roxy and the Devil [English]', pageCount: 9),
      );
      final GalleryIdentity zh = GalleryIdentity.fromGallery(
        _ehGallery(gid: 3, title: '[Dross] Roxy and the Devil [Chinese] [個人漢化]', pageCount: 10),
      );
      final GalleryIdentity pt = GalleryIdentity.fromGallery(
        _ehGallery(gid: 4, title: '[Dross] Roxy and the Devil [Portuguese]', pageCount: 9),
      );

      expect(GalleryIdentityMatcher.match(jp, en), isNotNull);
      expect(GalleryIdentityMatcher.match(en, zh), isNotNull);
      expect(GalleryIdentityMatcher.match(en, pt), isNotNull);
    });

    test('matches translated title with Kanji vs Romaji artist via perceptual cover hash', () {
      final CoverPerceptualHash? cover = CoverPerceptualHash.fromRgba9x9(_syntheticCoverRgba(seed: 55));
      final GalleryIdentity jp = GalleryIdentity.fromGallery(
        _ehGallery(gid: 10, title: '[八尋ぽち] 秘密のレッスン', pageCount: 24),
        coverHash: cover,
      );
      final GalleryIdentity pt = GalleryIdentity.fromGallery(
        _ehGallery(gid: 11, title: '[Yahiro Pochi] Aula Secreta [Portuguese]', pageCount: 24),
        coverHash: cover,
      );

      expect(GalleryIdentityMatcher.match(jp, pt), isNotNull);
    });
  });

  group('GalleryIdentityMatcher — false-positive guards', () {
    test('never self-matches the exact same gid', () {
      final GalleryIdentity a = GalleryIdentity.fromGallery(
        _ehGallery(gid: 1, title: '[Dross] Roxy and the Devil', pageCount: 9),
      );
      final GalleryIdentity same = GalleryIdentity.fromGallery(
        _ehGallery(gid: 1, title: '[Dross] Roxy and the Devil', pageCount: 9),
      );

      expect(GalleryIdentityMatcher.match(a, same), isNull);
    });

    test('strictly rejects sequels / different chapter numbers even with identical covers', () {
      final CoverPerceptualHash? sameCover = CoverPerceptualHash.fromRgba9x9(_syntheticCoverRgba(seed: 7));
      expect(sameCover, isNotNull);

      final GalleryIdentity ep7 = GalleryIdentity.fromGallery(
        _ehGallery(title: '[Creator] Lust Flight 07 [English]', pageCount: 76),
        coverHash: sameCover,
      );
      final GalleryIdentity ep8 = GalleryIdentity.fromGallery(
        _xlecxGallery(title: 'Lust Flight 08', pageCount: 76),
        coverHash: sameCover,
      );

      expect(GalleryIdentityMatcher.match(ep7, ep8), isNull);
    });

    test('strictly rejects Part 1 vs Part 2 and Roman numeral sequels', () {
      final GalleryIdentity part1 = GalleryIdentity.fromGallery(
        _ehGallery(title: '[Artist] Midnight Adventure Part II', pageCount: 30),
      );
      final GalleryIdentity part2 = GalleryIdentity.fromGallery(
        _xlecxGallery(title: 'Midnight Adventure Part III', pageCount: 30),
      );

      expect(GalleryIdentityMatcher.match(part1, part2), isNull);
    });

    test('rejects short/generic titles without creator or cover hash corroboration', () {
      final GalleryIdentity eh = GalleryIdentity.fromGallery(
        _ehGallery(title: '[ArtistA] Space Girls [English]', pageCount: 54, artists: <String>['artista']),
      );
      final GalleryIdentity xlecx = GalleryIdentity.fromGallery(
        _xlecxGallery(title: 'Space Girls', pageCount: 54),
      );

      expect(GalleryIdentityMatcher.match(eh, xlecx), isNull);
    });

    test('accepts short title once corroborated by matching cover hash', () {
      final CoverPerceptualHash? hash = CoverPerceptualHash.fromRgba9x9(_syntheticCoverRgba(seed: 19));
      final GalleryIdentity eh = GalleryIdentity.fromGallery(
        _ehGallery(title: '[ArtistA] Space Girls [English]', pageCount: 54, artists: <String>['artista']),
        coverHash: hash,
      );
      final GalleryIdentity xlecx = GalleryIdentity.fromGallery(
        _xlecxGallery(title: 'Space Girls', pageCount: 54),
        coverHash: hash,
      );

      expect(GalleryIdentityMatcher.match(eh, xlecx), isNotNull);
    });

    test('rejects incompatible page counts (chapter vs compilation)', () {
      final GalleryIdentity single = GalleryIdentity.fromGallery(
        _ehGallery(title: '[H Bof 3DX] The Pink Crystal', pageCount: 20),
      );
      final GalleryIdentity full = GalleryIdentity.fromGallery(
        _xlecxGallery(title: 'The Pink Crystal', pageCount: 120),
      );

      expect(GalleryIdentityMatcher.match(single, full), isNull);
    });

    test('rejects when both sides have contradicting creators and no matching cover', () {
      final GalleryIdentity eh = GalleryIdentity.fromGallery(
        _ehGallery(title: '[Alpha Studio] Chronicles of the Golden Castle', pageCount: 32, artists: <String>['alpha studio']),
      );
      final GalleryIdentity xlecx = GalleryIdentity.fromGallery(
        _xlecxGallery(title: 'Chronicles of the Golden Castle [Beta Works]', pageCount: 32, uploader: 'Beta Works'),
      );

      expect(GalleryIdentityMatcher.match(eh, xlecx), isNull);
    });

    test('rejects unrelated covers with different hashes', () {
      final CoverPerceptualHash? h1 = CoverPerceptualHash.fromRgba9x9(_syntheticCoverRgba(seed: 3));
      final CoverPerceptualHash? h2 = CoverPerceptualHash.fromRgba9x9(_syntheticCoverRgba(seed: 99));
      expect(h1, isNotNull);
      expect(h2, isNotNull);
      expect(h1!.hammingDistance(h2!), greaterThan(30));
    });

    test('rejects flat/blank covers as uninformative', () {
      final Uint8List flat = Uint8List.fromList(List<int>.filled(9 * 9 * 4, 200));
      expect(CoverPerceptualHash.fromRgba9x9(flat), isNull);
    });

    test('CoverPerceptualHash hex serialization round-trips cleanly', () {
      final CoverPerceptualHash? hash = CoverPerceptualHash.fromRgba9x9(_syntheticCoverRgba(seed: 11));
      expect(hash, isNotNull);
      final String hex = hash!.toHex();
      expect(hex.length, 32);
      expect(CoverPerceptualHash.tryParse(hex), equals(hash));
    });
  });
}
