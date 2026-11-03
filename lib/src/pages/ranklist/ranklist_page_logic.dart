import 'dart:async';

import 'package:acervo_hc/src/network/eh_request.dart';
import 'package:acervo_hc/src/pages/ranklist/ranklist_page_state.dart';
import 'package:acervo_hc/src/utils/eh_spider_parser.dart';
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
    super.handleClearAndRefresh();
  }

  @override
  Future<List<dynamic>> getGalleriesAndPageInfoByPage(int pageIndex) async {
    log.info('Get ranklist data, type:${state.ranklistType.name}, pageIndex:$pageIndex');

    return await ehRequest.requestRanklistPage(
      ranklistType: state.ranklistType,
      pageNo: pageIndex,
      parser: EHSpiderParser.ranklistPage2GalleryPageInfo,
    );
  }
}
