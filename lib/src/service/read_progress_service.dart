import 'package:get/get.dart';
import 'package:acervo_hc/src/enum/config_enum.dart';
import 'package:acervo_hc/src/extension/get_logic_extension.dart';
import 'package:acervo_hc/src/service/jh_service.dart';
import 'package:acervo_hc/src/service/local_config_service.dart';

ReadProgressService readProgressService = ReadProgressService();

class ReadProgressService extends GetxController with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String readProgressUpdateId = 'readProgress';

  @override
  List<JHLifeCircleBean> get initDependencies => super.initDependencies..addAll([localConfigService]);

  /// Cache for read progress: gid -> readIndex
  final Map<String, int> _progressCache = {};

  @override
  Future<void> doInitBean() async {
    Get.put(this, permanent: true);
  }

  @override
  Future<void> doAfterBeanReady() async {}

  /// Get read progress for a gallery with cache
  Future<int> getReadProgress(int gid) async {
    // Return from cache if available
    if (_progressCache.containsKey(gid.toString())) {
      return _progressCache[gid.toString()]!;
    }

    // Read from storage
    final data = await localConfigService.read(
      configKey: ConfigEnum.readIndexRecord,
      subConfigKey: gid.toString(),
    );

    final progress = int.tryParse(data ?? '') ?? 0;
    _progressCache[gid.toString()] = progress;
    return progress;
  }

  /// Cached read progress for a gallery, or null when it was never loaded.
  /// Cards use this to avoid scheduling a future (and an extra rebuild) per
  /// build; [preloadReadProgress] fills the cache for a whole gallery page.
  int? cachedReadProgress(int gid) => _progressCache[gid.toString()];

  /// Loads the read progress of [gids] that aren't cached yet, then notifies
  /// the cards of the galleries that actually had progress.
  Future<void> preloadReadProgress(Iterable<int> gids) async {
    final List<int> missing = gids.where((gid) => !_progressCache.containsKey(gid.toString())).toList();
    if (missing.isEmpty) {
      return;
    }
    await Future.wait(missing.map(getReadProgress));
    for (final int gid in missing) {
      updateSafely(['$readProgressUpdateId::$gid']);
    }
  }

  /// Delete read progress for a gallery and notify listeners
  Future<void> deleteReadProgress(String recordKey) async {
    _progressCache.remove(recordKey);
    await localConfigService.delete(
      configKey: ConfigEnum.readIndexRecord,
      subConfigKey: recordKey,
    );
    updateSafely(['$readProgressUpdateId::$recordKey']);
  }

  /// Update read progress and notify listeners
  Future<void> updateReadProgress(String recordKey, int index) async {
    _progressCache[recordKey] = index;
    await localConfigService.write(
      configKey: ConfigEnum.readIndexRecord,
      subConfigKey: recordKey,
      value: index.toString(),
    );
    updateSafely(['$readProgressUpdateId::$recordKey']);
  }

  /// When a newer version of an E-Hentai gallery has no reading progress yet
  /// and its parent gallery does, copy the parent's progress clamped to the
  /// new gallery's [pageCount]. Leaves the parent's progress untouched.
  Future<bool> inheritProgressFromParent({
    required int gid,
    required int parentGid,
    required int pageCount,
  }) async {
    if (gid == parentGid || pageCount <= 0) {
      return false;
    }
    final int current = await getReadProgress(gid);
    if (current > 0) {
      return false;
    }
    final int parentProgress = await getReadProgress(parentGid);
    if (parentProgress <= 0) {
      return false;
    }
    final int clamped = parentProgress >= pageCount ? pageCount - 1 : parentProgress;
    await updateReadProgress(gid.toString(), clamped);
    return true;
  }
}
