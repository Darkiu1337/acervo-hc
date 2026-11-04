import 'dart:convert';

import 'package:get/get.dart';
import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/storage_service.dart';

AlreadyReadService alreadyReadService = AlreadyReadService();

/// Galleries manually marked as "already read".
///
/// The list has two roles:
///  1. it hides the gallery from the listing pages (home, search, popular,
///     watched and the Xlecx source), so already seen works do not come back;
///  2. it is the source of the "Already read" page in the sidebar, where they
///     can be inspected and removed.
///
/// Works for both sources (E-H and Xlecx) because a `GalleryHistoryModel`
/// already carries a [GalleryUrl] that knows its source. Stored in GetStorage
/// as a JSON array (same rationale as the local favorites: no Drift schema
/// change and no `build_runner` codegen), newest first.
class AlreadyReadService {
  static const String _storageKey = 'alreadyReadGalleries';

  /// Rows per page of the "Already read" page.
  static const int pageSize = 100;

  final RxList<GalleryHistoryModel> galleries = <GalleryHistoryModel>[].obs;

  /// gids in [galleries], for fast checks while filtering listings/cards.
  final RxSet<int> gids = <int>{}.obs;

  bool _restored = false;

  int get count => galleries.length;

  /// Loads the stored list once, before the first read from a build.
  void ensureRestored() {
    if (_restored) {
      return;
    }
    _restored = true;

    try {
      final String? raw = storageService.read<String>(_storageKey);
      if (raw == null || raw.isEmpty) {
        return;
      }

      final List<dynamic> decoded = jsonDecode(raw) as List;
      for (final dynamic entry in decoded) {
        try {
          final GalleryHistoryModel gallery = GalleryHistoryModel.fromJson(Map<String, dynamic>.from(entry as Map));
          galleries.add(gallery);
          gids.add(gallery.galleryUrl.gid);
        } catch (e) {
          log.error('Restore already-read entry failed', e);
        }
      }
    } catch (e) {
      log.error('Restore already-read galleries failed', e);
    }
  }

  bool contains(int gid) {
    ensureRestored();
    return gids.contains(gid);
  }

  /// Returns `true` when the gallery is marked as read after this call.
  Future<bool> toggle(GalleryHistoryModel gallery) async {
    ensureRestored();
    final bool alreadyRead = gids.contains(gallery.galleryUrl.gid);

    if (alreadyRead) {
      await remove(gallery.galleryUrl.gid);
    } else {
      await add(gallery);
    }

    return !alreadyRead;
  }

  Future<void> add(GalleryHistoryModel gallery) async {
    ensureRestored();

    final List<GalleryHistoryModel> next = List<GalleryHistoryModel>.of(galleries);
    next.removeWhere((GalleryHistoryModel e) => e.galleryUrl.gid == gallery.galleryUrl.gid);
    next.insert(0, gallery);

    /// Update both stores before notifying, and notify exactly once: listeners
    /// reload synchronously, so they must observe the final list (the first
    /// notification of a remove-then-insert sequence used to be delivered while
    /// the new gallery was still missing).
    gids.add(gallery.galleryUrl.gid);
    galleries.value = next;

    await _persist();
  }

  Future<void> remove(int gid) async {
    ensureRestored();
    if (!gids.contains(gid)) {
      return;
    }

    final List<GalleryHistoryModel> next = List<GalleryHistoryModel>.of(galleries)
      ..removeWhere((GalleryHistoryModel e) => e.galleryUrl.gid == gid);

    gids.remove(gid);
    galleries.value = next;

    await _persist();
  }

  Future<void> clear() async {
    ensureRestored();
    gids.clear();
    galleries.value = <GalleryHistoryModel>[];
    await _persist();
  }

  int getPageCount() {
    ensureRestored();
    return galleries.isEmpty ? 0 : (galleries.length - 1) ~/ pageSize + 1;
  }

  List<GalleryHistoryModel> getByPageIndex(int pageIndex) {
    ensureRestored();
    return galleries.skip(pageIndex * pageSize).take(pageSize).toList();
  }

  Future<void> _persist() {
    return storageService.write(_storageKey, jsonEncode(galleries.toList()));
  }
}
