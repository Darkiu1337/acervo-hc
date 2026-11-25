import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:acervo_hc/src/enum/config_type_enum.dart';
import 'package:acervo_hc/src/model/config.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/service/acervo_backup_service.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/service/watched_progress_service.dart';
import 'package:acervo_hc/src/utils/atomic_json_store.dart';
import 'package:flutter_test/flutter_test.dart';

GalleryHistoryModel _history(int gid, String title, {String? coverHash}) {
  return GalleryHistoryModel(
    galleryUrl: GalleryUrl(isEH: true, gid: gid, token: '0123456789'),
    title: title,
    category: 'Doujinshi',
    coverUrl: 'https://example.com/$gid.jpg',
    pageCount: 24,
    rating: 4.5,
    language: 'english',
    uploader: 'artist',
    publishTime: '2026-01-01 12:00',
    isExpunged: false,
    tags: const <String>[],
    coverHash: coverHash,
  );
}

Gallery _gallery(int externalId, String title) {
  return Gallery(
    galleryUrl: GalleryUrl.nhentaiGalleryUrl(externalId),
    title: title,
    category: 'Doujinshi',
    cover: GalleryImage(url: 'https://example.com/$externalId.jpg'),
    pageCount: 30,
    rating: 0,
    hasRated: false,
    publishTime: '2026-01-01 12:00',
    isExpunged: false,
    tags: LinkedHashMap<String, List<GalleryTag>>(),
  );
}

void main() {
  group('AcervoBackupService', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('acervo_backup_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('exports, inspects, and merges Already Read (preserving coverHash), Local Favorites (with collections), and Watched Progress', () async {
      final AlreadyReadService srcRead = AlreadyReadService(
        store: AtomicJsonStore(directoryProvider: () => tempDir, fileName: 'src_read.json'),
      );
      final LocalFavoriteService srcFav = LocalFavoriteService(
        store: AtomicJsonStore(directoryProvider: () => tempDir, fileName: 'src_fav.json'),
      );
      await srcRead.restoreAsync();
      await srcFav.restoreAsync();

      await srcRead.add(_history(100, 'Work A', coverHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
      await srcRead.add(_history(200, 'Work B'));

      final Gallery g1 = _gallery(12345, 'NH Work 1');
      final Gallery g2 = _gallery(67890, 'NH Work 2');
      await srcFav.add(g1, initialCollections: <String>['Sci-Fi']);
      await srcFav.add(g2);

      final WatchedProgressService watched = WatchedProgressService.instance;
      watched.loadFromJsonString(jsonEncode(<String, dynamic>{
        'seenGids': <int>[1, 2],
        'bookmarks': <Map<String, dynamic>>[
          const WatchedBookmark(gid: 1, title: 'BM 1', createdAtMs: 1000).toJson(),
        ],
        'lastAnchor': const WatchedBookmark(gid: 2, title: 'Anchor 2', createdAtMs: 2000).toJson(),
      }));

      final Map<String, dynamic> exported = await acervoBackupService.buildBackupMap(
        sections: <AcervoBackupSection>{
          AcervoBackupSection.alreadyRead,
          AcervoBackupSection.localFavorites,
          AcervoBackupSection.watchedProgress,
        },
        appVersion: '1.5.1+10',
        alreadyRead: srcRead,
        localFavorites: srcFav,
        watchedProgress: watched,
        includeLegacyCloudSections: false,
      );

      final String rawJson = await acervoBackupService.encodeBackup(exported);
      final AcervoBackupDocument doc = await acervoBackupService.inspectBackup(rawJson);

      expect(doc.isLegacyFormat, isFalse);
      expect(doc.appVersion, '1.5.1+10');
      expect(doc.sectionCounts[AcervoBackupSection.alreadyRead], 2);
      expect(doc.sectionCounts[AcervoBackupSection.localFavorites], 2);

      // Prepare target device with partially overlapping data.
      final AlreadyReadService dstRead = AlreadyReadService(
        store: AtomicJsonStore(directoryProvider: () => tempDir, fileName: 'dst_read.json'),
      );
      final LocalFavoriteService dstFav = LocalFavoriteService(
        store: AtomicJsonStore(directoryProvider: () => tempDir, fileName: 'dst_fav.json'),
      );
      await dstRead.restoreAsync();
      await dstFav.restoreAsync();

      await dstRead.add(_history(100, 'Work A')); // missing coverHash on target
      await dstRead.add(_history(300, 'Work C'));
      await dstFav.add(g1, initialCollections: <String>['LocalOnly']);

      watched.loadFromJsonString(jsonEncode(<String, dynamic>{
        'seenGids': <int>[2, 3],
        'bookmarks': <Map<String, dynamic>>[
          const WatchedBookmark(gid: 3, title: 'BM 3', createdAtMs: 3000).toJson(),
        ],
        'lastAnchor': const WatchedBookmark(gid: 3, title: 'Anchor 3', createdAtMs: 1500).toJson(),
      }));

      await acervoBackupService.importBackup(
        doc,
        sections: doc.availableSections,
        mode: AcervoBackupImportMode.merge,
        alreadyRead: dstRead,
        localFavorites: dstFav,
        watchedProgress: watched,
        persistWatched: false,
      );

      expect(dstRead.gids, containsAll(<int>[100, 200, 300]));
      expect(dstRead.galleries.firstWhere((e) => e.galleryUrl.gid == 100).coverHash, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(dstFav.favorites.length, 2);
      expect(dstFav.collectionsOf(g1.gid), containsAll(<String>['LocalOnly', 'Sci-Fi']));
      expect(watched.seenGids, containsAll(<int>[1, 2, 3]));
      expect(watched.bookmarks.map((b) => b.gid).toList(), <int>[3, 1]);
      expect(watched.lastAnchor?.gid, 2); // newer timestamp (2000 > 1500)

      // Now test Replace mode.
      await acervoBackupService.importBackup(
        doc,
        sections: <AcervoBackupSection>{AcervoBackupSection.alreadyRead, AcervoBackupSection.localFavorites},
        mode: AcervoBackupImportMode.replace,
        alreadyRead: dstRead,
        localFavorites: dstFav,
        watchedProgress: watched,
        persistWatched: false,
      );

      expect(dstRead.gids, <int>{100, 200});
      expect(dstFav.collectionsOf(g1.gid), <String>['Sci-Fi']);
    });

    test('parses legacy JHenTaiConfig JSON array format seamlessly', () async {
      final List<Map<String, dynamic>> legacy = <Map<String, dynamic>>[
        CloudConfig(
          id: -1,
          shareCode: 'local',
          identificationCode: 'local',
          type: CloudConfigTypeEnum.searchHistory,
          version: '1.0.0',
          config: jsonEncode(<String>['full color', 'portuguese']),
          ctime: DateTime.utc(2026, 1, 1),
        ).toJson(),
      ];

      final AcervoBackupDocument doc = await acervoBackupService.inspectBackup(jsonEncode(legacy));
      expect(doc.isLegacyFormat, isTrue);
      expect(doc.availableSections, <AcervoBackupSection>{AcervoBackupSection.searchHistory});
      expect(doc.sectionCounts[AcervoBackupSection.searchHistory], 2);
    });
  });
}
