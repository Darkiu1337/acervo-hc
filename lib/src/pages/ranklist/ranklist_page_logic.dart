import 'dart:async';

import 'package:get/get.dart';
import 'package:acervo_hc/src/extension/get_logic_extension.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';
import 'package:acervo_hc/src/network/eh_request.dart';
import 'package:acervo_hc/src/pages/ranklist/ranklist_page_state.dart';
import 'package:acervo_hc/src/utils/eh_spider_parser.dart';
import 'package:acervo_hc/src/widget/eh_client_filter_dialog.dart';
import 'package:acervo_hc/src/widget/eh_search_config_dialog.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

import '../../service/log.dart';
import '../base/old_base_page_logic.dart';

class RanklistPageLogic extends OldBasePageLogic {
  @override
  final RanklistPageState state = RanklistPageState();

  @override
  bool get useSearchConfig => false;

  /// A ranking is a reference list, not a browsing feed; keep it complete.
  @override
  bool get hideAlreadyReadGalleries => false;

  Future<void> handleChangeRanklist(RanklistType newType) async {
    if (state.loadingState == LoadingState.loading) {
      return;
    }
    if (newType == state.ranklistType) {
      return;
    }

    state.ranklistType = newType;
    state.rawGalleries.clear();
    super.handleClearAndRefresh();
  }

  @override
  Future<void> handleClearAndRefresh() {
    state.rawGalleries.clear();
    return super.handleClearAndRefresh();
  }

  @override
  Future<List<dynamic>> getGalleriesAndPageInfoByPage(int pageIndex) async {
    log.info('Get ranklist data, type:${state.ranklistType.name}, pageIndex:$pageIndex');

    final List<dynamic> result = await ehRequest.requestRanklistPage(
      ranklistType: state.ranklistType,
      pageNo: pageIndex,
      parser: EHSpiderParser.ranklistPage2GalleryPageInfo,
    );

    final List<Gallery> fetched = (result[0] as List<Gallery>);
    if (pageIndex == 0) {
      state.rawGalleries
        ..clear()
        ..addAll(fetched);
    } else {
      for (final Gallery g in fetched) {
        if (!state.rawGalleries.any((existing) => existing.gid == g.gid)) {
          state.rawGalleries.add(g);
        }
      }
    }

    result[0] = state.clientFilter.apply(fetched);
    return result;
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
