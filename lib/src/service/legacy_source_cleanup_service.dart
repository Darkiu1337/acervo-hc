import 'dart:convert';

import 'package:acervo_hc/src/database/database.dart';
import 'package:acervo_hc/src/service/jh_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/path_service.dart';
import 'package:acervo_hc/src/service/storage_service.dart';
import 'package:drift/drift.dart';

LegacySourceCleanupService legacySourceCleanupService = LegacySourceCleanupService();

/// One-shot purge of the local data left by a gallery source that was removed
/// from the app.
///
/// That source shared the E-Hentai tables, storage keys and gid space, so its
/// leftovers would otherwise be restored at startup and then fail to parse
/// (GalleryUrl.parse no longer knows the site) or show up as broken
/// favorites, downloads and history entries.
///
/// Only the local records are removed, never the image files on disk: a purge
/// that deletes user files is too destructive for an automatic migration.
class LegacySourceCleanupService with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  /// Domain marker of the retired source, present in every url it stored.
  static const String _galleryUrlMarker = '8muses.io';

  /// Image hosts of the retired source, used to drop cached responses.
  static const String _cacheUrlMarker = '8muses';

  /// Keys whose JSON list holds gallery snapshots with a `galleryUrl` field.
  static const List<String> _storageKeys = <String>[
    'localFavorites',
    'alreadyReadGalleries',
  ];

  static const String _doneKey = 'legacySourceCleanup_v1';

  /// Must run before the services that load these rows into memory at startup.
  @override
  List<JHLifeCircleBean> get initDependencies => <JHLifeCircleBean>[pathService, log, storageService];

  @override
  Future<void> doInitBean() async {
    if (storageService.read<bool>(_doneKey) == true) {
      return;
    }

    await _purgeStoredLists();
    await _purgeDatabase();
    await storageService.write(_doneKey, true);

    log.info('Removed the local data of the retired gallery source');
  }

  @override
  Future<void> doAfterBeanReady() async {}

  /// Drops the retired entries from the local lists, keeping every other
  /// source untouched (the lists are shared with E-Hentai and Xlecx).
  Future<void> _purgeStoredLists() async {
    for (final String key in _storageKeys) {
      final String? raw = storageService.read<String>(key);
      if (raw == null || raw.isEmpty) {
        continue;
      }

      try {
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        final List<dynamic> kept = decoded.where((dynamic entry) {
          final Object? url = entry is Map ? entry['galleryUrl'] : null;
          return url is! String || !url.contains(_galleryUrlMarker);
        }).toList();

        if (kept.length == decoded.length) {
          continue;
        }

        await storageService.write(key, jsonEncode(kept));
        log.info('Purged ${decoded.length - kept.length} retired entries from $key');
      } catch (e, stack) {
        log.error('Purge retired entries from $key failed', e, stack);
      }
    }
  }

  Future<void> _purgeDatabase() async {
    const String marker = '%$_galleryUrlMarker%';

    await appDb.transaction(() async {
      /// Collect the gids first: the derived rows are only reachable through
      /// the gallery row, which is deleted below.
      final List<int> gids = (await (appDb.selectOnly(appDb.galleryDownloaded)
                ..addColumns([appDb.galleryDownloaded.gid])
                ..where(appDb.galleryDownloaded.galleryUrl.like(marker)))
              .get())
          .map((row) => row.read(appDb.galleryDownloaded.gid)!)
          .toList();

      if (gids.isNotEmpty) {
        await (appDb.delete(appDb.image)..where((t) => t.gid.isIn(gids))).go();
        await (appDb.delete(appDb.superResolutionInfo)..where((t) => t.gid.isIn(gids))).go();
        await (appDb.delete(appDb.oldSuperResolutionInfo)..where((t) => t.gid.isIn(gids))).go();
        await (appDb.delete(appDb.galleryDownloaded)..where((t) => t.gid.isIn(gids))).go();
      }

      await (appDb.delete(appDb.galleryDownloadedOld)..where((t) => t.galleryUrl.like(marker))).go();
      await (appDb.delete(appDb.galleryHistoryV2)..where((t) => t.jsonBody.like(marker))).go();
      await (appDb.delete(appDb.galleryHistory)..where((t) => t.jsonBody.like(marker))).go();
      await (appDb.delete(appDb.archiveDownloaded)..where((t) => t.galleryUrl.like(marker))).go();
      await (appDb.delete(appDb.archiveDownloadedOld)..where((t) => t.galleryUrl.like(marker))).go();
      await (appDb.delete(appDb.dioCache)..where((t) => t.url.like('%$_cacheUrlMarker%'))).go();
    });
  }
}
