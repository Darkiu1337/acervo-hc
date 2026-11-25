import 'dart:io';

import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/utils/atomic_json_store.dart';
import 'package:flutter_test/flutter_test.dart';

GalleryHistoryModel _makeHistoryEntry({
  required int gid,
  required String title,
  String? coverHash,
}) {
  return GalleryHistoryModel(
    galleryUrl: GalleryUrl(isEH: true, gid: gid, token: 'abcdef1234'),
    title: title,
    category: 'Doujinshi',
    coverUrl: 'https://example.com/$gid.jpg',
    pageCount: 24,
    rating: 4.5,
    language: 'english',
    uploader: 'artist_a',
    publishTime: '2026-01-01 12:00',
    isExpunged: false,
    tags: const <String>[],
    coverHash: coverHash,
  );
}

void main() {
  group('AtomicJsonStore', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('atomic_json_store_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('writes atomically, reads back, and leaves no temp file behind', () async {
      final AtomicJsonStore store = AtomicJsonStore(
        directoryProvider: () => tempDir,
        fileName: 'data.json',
      );

      expect(await store.readJson(), isNull);

      await store.writeJson(<String, dynamic>{'hello': 'world', 'count': 42});
      expect(store.file.existsSync(), isTrue);
      expect(File('${store.file.path}.tmp').existsSync(), isFalse);

      final dynamic loaded = await store.readJson();
      expect(loaded, isA<Map<String, dynamic>>());
      expect((loaded as Map<String, dynamic>)['hello'], 'world');
      expect(loaded['count'], 42);
    });

    test('serializes overlapping concurrent writes in call order', () async {
      final AtomicJsonStore store = AtomicJsonStore(
        directoryProvider: () => tempDir,
        fileName: 'concurrent.json',
      );

      final List<Future<void>> writes = <Future<void>>[
        for (int i = 1; i <= 20; i++) store.writeJson(<String, int>{'seq': i}),
      ];
      await Future.wait(writes);

      final Map<String, dynamic> finalData = Map<String, dynamic>.from(await store.readJson() as Map);
      expect(finalData['seq'], 20);
      expect(File('${store.file.path}.tmp').existsSync(), isFalse);
    });

    test('AlreadyReadService persists and restores asynchronously via AtomicJsonStore', () async {
      final AtomicJsonStore store = AtomicJsonStore(
        directoryProvider: () => tempDir,
        fileName: 'already_read.json',
      );

      final AlreadyReadService writer = AlreadyReadService(store: store);
      await writer.restoreAsync();
      await writer.add(_makeHistoryEntry(gid: 101, title: 'Sample Gallery', coverHash: '0123456789abcdef0123456789abcdef'));

      final AlreadyReadService reader = AlreadyReadService(store: store);
      await reader.restoreAsync();

      expect(reader.count, 1);
      expect(reader.contains(101), isTrue);
      expect(reader.galleries.first.coverHash, '0123456789abcdef0123456789abcdef');
    });
  });
}
