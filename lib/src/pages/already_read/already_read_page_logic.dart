import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/widget/eh_alert_dialog.dart';
import 'package:acervo_hc/src/widget/eh_context_menu.dart';

import '../../model/gallery.dart';
import '../../model/gallery_history_model.dart';
import '../../utils/convert_util.dart';
import '../base/old_base_page_logic.dart';
import 'already_read_page_state.dart';

/// Lists the galleries manually marked as "already read" (hidden from the
/// listing pages) and lets them be removed again.
class AlreadyReadPageLogic extends OldBasePageLogic {
  @override
  final AlreadyReadPageState state = AlreadyReadPageState();

  @override
  bool get useSearchConfig => false;

  /// This page exists to show them, so it must not hide them.
  @override
  bool get hideAlreadyReadGalleries => false;

  Worker? _alreadyReadWorker;

  @override
  Future<void> onInit() async {
    alreadyReadService.ensureRestored();
    await super.onInit();

    /// Keep the list in sync when a gallery is marked/unmarked from another
    /// page (details or a Xlecx card menu). Deferred to a microtask so the
    /// reload observes the list after the mutation completes.
    _alreadyReadWorker = ever(alreadyReadService.galleries, (_) {
      if (!isClosed) {
        Future.microtask(handleClearAndRefresh);
      }
    });
  }

  @override
  void onClose() {
    _alreadyReadWorker?.dispose();
    super.onClose();
  }

  @override
  Future<List<dynamic>> getGalleriesAndPageInfoByPage(int pageIndex) async {
    final int pageCount = alreadyReadService.getPageCount();
    final List<GalleryHistoryModel> models = alreadyReadService.getByPageIndex(pageIndex);
    final List<Gallery> galleries = models.map(galleryHistoryModel2Gallery).toList();

    return [
      galleries,
      pageCount,
      pageIndex >= 1 ? pageIndex - 1 : null,
      pageIndex < pageCount - 1 ? pageIndex + 1 : null,
    ];
  }

  Future<void> handleTapDeleteButton() async {
    bool? result = await Get.dialog(EHDialog(title: '${'deleteAll'.tr}?'));

    if (result == true) {
      await alreadyReadService.clear();
    }
  }

  @override
  void handleLongPressCard(BuildContext context, Gallery gallery, {Offset? position}) {
    showEHContextMenu(
      context,
      position: position,
      actions: [
        EHContextMenuAction(
          text: 'removeFromAlreadyRead'.tr,
          icon: const Icon(Icons.check_circle_outline, size: 18),
          color: UIConfig.alertColor(context),
          onTap: () => remove(gallery.gid),
        ),
      ],
    );
  }

  @override
  void handleSecondaryTapCard(BuildContext context, Gallery gallery, {Offset? position}) {
    handleLongPressCard(context, gallery, position: position);
  }

  Future<void> remove(int gid) async {
    await alreadyReadService.remove(gid);
  }
}
