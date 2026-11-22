import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/read_page_info.dart';
import 'package:acervo_hc/src/widget/eh_wheel_scroll_listener.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../../../setting/read_setting.dart';
import '../../spread_pages.dart';
import '../base/base_layout.dart';
import '../base/base_layout_logic.dart';
import 'horizontal_page_layout_logic.dart';
import 'horizontal_page_layout_state.dart';

class HorizontalPageLayout extends BaseLayout {
  HorizontalPageLayout({Key? key}) : super(key: key);

  @override
  final HorizontalPageLayoutLogic logic = Get.put<HorizontalPageLayoutLogic>(HorizontalPageLayoutLogic(), permanent: true);

  final HorizontalPageLayoutState state = Get.find<HorizontalPageLayoutLogic>().state;

  @override
  Widget buildBody(BuildContext context) {
    logic.syncToCurrentImageIndex();
    logic.onViewportChanged(readPageState.displayRegionSize);
    final PageParts parts = logic.pageParts;
    final bool rightHalfFirst = showRightHalfFirst(
      isRightToLeftOrVertical: logic.readPageLogic.isInRight2LeftDirection,
      reverseOrder: readSetting.reverseSplitWidePages.isTrue,
    );

    return EHWheelListener(
      onPointerScroll: logic.readPageLogic.isInFitWidthReadDirection ? null : logic.onPointerScroll,
      child: PhotoViewGallery.builder(
        enableCtrlScrollZoom: true,
        ctrlScrollZoomFactor: logic.zoomStep,
        itemCount: parts.pageCount,
        scrollPhysics: const ClampingScrollPhysics(),
        pageController: logic.pageController,
        cacheExtent: readPageState.readPageInfo.mode == ReadMode.online
            ? readSetting.preloadPageCount.value.toDouble()
            : readSetting.preloadPageCountLocal.value.toDouble(),
        reverse: logic.readPageLogic.isInRight2LeftDirection,
        builder: (context, pageIndex) {
          final int imageIndex = parts.imageOf(pageIndex);
          final ImagePart part = parts.partOf(pageIndex);
          return PhotoViewGalleryPageOptions.customChild(
            controller: logic.pageViewControllerFor(pageIndex),
            scaleStateController: logic.scaleStateControllerFor(pageIndex),
            initialScale: 1.0,
            minScale: 1.0,
            maxScale: BaseLayoutLogic.maxZoomScale,
            scaleStateCycle: readSetting.enableDoubleTapToScaleUp.isTrue ? logic.scaleStateCycle : null,
            enableTapDragZoom: readSetting.enableTapDragToScaleUp.isTrue,
            child: Obx(() {
              Widget item = readPageState.readPageInfo.mode == ReadMode.online
                  ? buildItemInOnlineMode(context, imageIndex)
                  : buildItemInLocalMode(context, imageIndex);

              if (part != ImagePart.whole) {
                item = FittedBox(
                  fit: logic.readPageLogic.isInFitWidthReadDirection ? BoxFit.fitWidth : BoxFit.contain,
                  child: SplitHalfClipper(
                    showRightHalf: isRightHalfForPart(part, rightHalfFirst: rightHalfFirst),
                    child: item,
                  ),
                );
              }

              if (logic.readPageLogic.isInFitWidthReadDirection) {
                item = Center(child: SingleChildScrollView(controller: state.scrollControllerOf(pageIndex), child: item));
              }

              return item;
            }),
          );
        },
      ),
    );
  }
}
