import 'package:get/get.dart';
import 'package:acervo_hc/src/extension/get_logic_extension.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';
import 'package:acervo_hc/src/widget/eh_client_filter_dialog.dart';
import 'package:acervo_hc/src/widget/eh_search_config_dialog.dart';

import '../base/base_page_logic.dart';
import 'popular_page_state.dart';

class PopularPageLogic extends BasePageLogic {
  @override
  final PopularPageState state = PopularPageState();

  @override
  bool get useSearchConfig => false;

  @override
  Future<List<Gallery>> postHandleNewGalleries(List<Gallery> galleries, {bool cleanDuplicate = true}) async {
    final List<Gallery> processed = await super.postHandleNewGalleries(galleries, cleanDuplicate: cleanDuplicate);
    if (!cleanDuplicate) {
      state.rawGalleries
        ..clear()
        ..addAll(processed);
    } else {
      for (final Gallery g in processed) {
        if (!state.rawGalleries.any((existing) => existing.gid == g.gid)) {
          state.rawGalleries.add(g);
        }
      }
    }
    return state.clientFilter.apply(processed);
  }

  @override
  Future<void> handleTapFilterButton([
    EHSearchConfigDialogType searchConfigDialogType = EHSearchConfigDialogType.filter,
  ]) async {
    final GalleryClientFilter? result = await Get.dialog<GalleryClientFilter>(
      EHClientFilterDialog(initialFilter: state.clientFilter),
    );
    if (result == null) {
      return;
    }
    state.clientFilter = result;
    state.galleries = state.clientFilter.apply(state.rawGalleries);
    updateSafely();
  }
}
