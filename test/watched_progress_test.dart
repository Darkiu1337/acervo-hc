import 'dart:convert';

import 'package:acervo_hc/src/service/watched_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WatchedBookmark & WatchedProgressService serialization', () {
    test('WatchedBookmark round-trips JSON', () {
      const WatchedBookmark original = WatchedBookmark(
        gid: 123456,
        title: 'Sample Watched Gallery',
        coverUrl: 'https://example.com/cover.jpg',
        createdAtMs: 1700000000000,
      );

      final WatchedBookmark restored = WatchedBookmark.fromJson(original.toJson());
      expect(restored.gid, original.gid);
      expect(restored.title, original.title);
      expect(restored.coverUrl, original.coverUrl);
      expect(restored.createdAtMs, original.createdAtMs);
    });

    test('WatchedProgressService loads and re-encodes seen gids, bookmarks, and anchor', () {
      final String payload = jsonEncode(<String, dynamic>{
        'seenGids': <int>[10, 20, 30],
        'bookmarks': <Map<String, dynamic>>[
          const WatchedBookmark(gid: 20, title: 'Bookmark 20', createdAtMs: 1000).toJson(),
        ],
        'lastAnchor': const WatchedBookmark(gid: 30, title: 'Anchor 30', createdAtMs: 2000).toJson(),
      });

      watchedProgressService.loadFromJsonString(payload);

      expect(watchedProgressService.seenCount, 3);
      expect(watchedProgressService.isSeen(10), isTrue);
      expect(watchedProgressService.isSeen(99), isFalse);
      expect(watchedProgressService.isBookmarked(20), isTrue);
      expect(watchedProgressService.isBookmarked(10), isFalse);
      expect(watchedProgressService.lastAnchor?.gid, 30);

      final Map<String, dynamic> reEncoded =
          jsonDecode(watchedProgressService.toJsonString()) as Map<String, dynamic>;
      expect(reEncoded['seenGids'], <int>[10, 20, 30]);
      expect((reEncoded['bookmarks'] as List).length, 1);
      expect((reEncoded['lastAnchor'] as Map)['gid'], 30);
    });
  });
}
