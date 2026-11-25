import 'dart:collection';
import 'dart:io';

import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';
import 'package:acervo_hc/src/model/gallery_url.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/utils/atomic_json_store.dart';
import 'package:flutter_test/flutter_test.dart';

Gallery _makeGallery({
  required int gid,
  required String title,
  GallerySource source = GallerySource.xlecx,
}) {
  final GalleryUrl url = source == GallerySource.eh
      ? GalleryUrl(isEH: true, gid: gid, token: '0123456789')
      : source == GallerySource.xlecx
          ? GalleryUrl.xlecxGalleryUrl(gid)
          : GalleryUrl.nhentaiGalleryUrl(gid);

  return Gallery(
    galleryUrl: url,
    title: title,
    category: 'Doujinshi',
    cover: GalleryImage(url: 'https://example.com/$gid.jpg'),
    pageCount: 20,
    rating: 4.5,
    hasRated: false,
    publishTime: '2026-01-01 12:00',
    isExpunged: false,
    tags: LinkedHashMap<String, List<GalleryTag>>(),
  );
}

void main() {
  group('LocalFavoriteService collections & persistence', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('local_fav_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates, renames, assigns, filters, and deletes collections cleanly', () async {
      final AtomicJsonStore store = AtomicJsonStore(
        directoryProvider: () => tempDir,
        fileName: 'local_favorites.json',
      );
      final LocalFavoriteService svc = LocalFavoriteService(store: store);
      await svc.restoreAsync();

      final Gallery g1 = _makeGallery(gid: 10, title: 'Comic One', source: GallerySource.xlecx);
      final Gallery g2 = _makeGallery(gid: 20, title: 'Doujin Two', source: GallerySource.nhentai);
      await svc.add(g1);
      await svc.add(g2);

      expect(await svc.createCollection('Coloridos'), isTrue);
      expect(await svc.createCollection('coloridos'), isFalse); // case-insensitive dedupe
      expect(await svc.createCollection('Reler'), isTrue);

      await svc.setGalleryCollections(g1.gid, <String>['Coloridos', 'Reler']);
      await svc.toggleGalleryInCollection(g2.gid, 'Reler');

      expect(svc.countInCollection('Coloridos'), 1);
      expect(svc.countInCollection('Reler'), 2);
      expect(svc.favoritesInCollection('Coloridos').map((g) => g.gid), <int>[g1.gid]);

      expect(await svc.renameCollection('Reler', 'Favoritos Top'), isTrue);
      expect(svc.collections, <String>['Coloridos', 'Favoritos Top']);
      expect(svc.collectionsOf(g2.gid), <String>['Favoritos Top']);

      // Reload from disk into a fresh instance to verify v2 persistence.
      final LocalFavoriteService reloaded = LocalFavoriteService(store: store);
      await reloaded.restoreAsync();
      expect(reloaded.favorites.length, 2);
      expect(reloaded.collections, <String>['Coloridos', 'Favoritos Top']);
      expect(reloaded.collectionsOf(g1.gid), <String>['Coloridos', 'Favoritos Top']);

      // Deleting a collection preserves galleries themselves.
      expect(await reloaded.deleteCollection('Favoritos Top'), isTrue);
      expect(reloaded.favorites.length, 2);
      expect(reloaded.collectionsOf(g2.gid), isEmpty);
      expect(reloaded.collectionsOf(g1.gid), <String>['Coloridos']);
    });

    test('loads legacy plain JSON array format seamlessly', () async {
      final AtomicJsonStore store = AtomicJsonStore(
        directoryProvider: () => tempDir,
        fileName: 'local_favorites.json',
      );
      final Gallery g1 = _makeGallery(gid: 55, title: 'Legacy Favorite');
      await store.writeJson(<Map<String, dynamic>>[g1.toJson()]);

      final LocalFavoriteService svc = LocalFavoriteService(store: store);
      await svc.restoreAsync();
      expect(svc.favorites.length, 1);
      expect(svc.favorites.first.gid, g1.gid);
      expect(svc.collections, isEmpty);
    });
  });
}
