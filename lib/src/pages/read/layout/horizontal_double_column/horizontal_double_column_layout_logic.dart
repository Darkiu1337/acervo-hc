import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/enum/config_enum.dart';
import 'package:acervo_hc/src/extension/get_logic_extension.dart';
import 'package:acervo_hc/src/service/local_config_service.dart';
import 'package:acervo_hc/src/utils/screen_size_util.dart';
import 'package:photo_view/photo_view.dart';

import '../../../../service/gallery_download/gallery_download_service.dart';
import '../../../../setting/read_setting.dart';
import '../base/base_layout_logic.dart';
import 'horizontal_double_column_layout_state.dart';

class HorizontalDoubleColumnLayoutLogic extends BaseLayoutLogic {
  HorizontalDoubleColumnLayoutState state = HorizontalDoubleColumnLayoutState();

  Completer<void> initCompleter = Completer<void>();

  int _lastPage = -1;

  /// Zoom level of the reading session, shared by every page. See
  /// [HorizontalPageLayoutLogic] for the rationale.
  double _desiredScale = 1.0;

  /// Page whose top alignment still has to be applied once its real content
  /// size is known.
  int? _pendingTopAlignPage;

  Size? _lastViewportSize;

  int get currentPageIndex {
    if (!initCompleter.isCompleted) {
      return 0;
    }
    final int fallback = computePageIndexOfImage(readPageState.readPageInfo.initialIndex);
    final int index = state.pageController.hasClients && state.pageController.page != null ? state.pageController.page!.round() : fallback;
    return index.clamp(0, state.pageCount - 1).toInt();
  }

  @override
  PhotoViewControllerBase? get activePhotoViewController => pageViewControllerFor(currentPageIndex);

  @override
  Size? get activeContentSize => initCompleter.isCompleted ? _contentSizeForPage(currentPageIndex) : null;

  @override
  PhotoViewControllerBase? photoViewControllerForPlaceholder(int imageIndex) {
    if (!initCompleter.isCompleted) {
      return null;
    }
    return pageViewControllerFor(computePageIndexOfImage(imageIndex));
  }

  /// Controller of [pageIndex], created with the zoom of the reading session
  /// already applied so the page is never painted at 1.0 before being zoomed.
  PhotoViewController pageViewControllerFor(int pageIndex) {
    final PhotoViewController? existing = state.photoViewControllers[pageIndex];
    if (existing != null) {
      return existing;
    }

    final Offset initialPosition = _initialPositionFor(pageIndex);
    final PhotoViewController controller = state.photoViewControllerOf(
      pageIndex,
      initialScale: _desiredScale,
      initialPosition: initialPosition,
    );
    _trackZoomOf(pageIndex, controller);
    return controller;
  }

  PhotoViewScaleStateController scaleStateControllerFor(int pageIndex) {
    final PhotoViewScaleStateController? existing = state.photoViewScaleStateControllers[pageIndex];
    if (existing != null) {
      return existing;
    }

    final PhotoViewScaleStateController controller = state.photoViewScaleStateControllerOf(pageIndex);
    controller.setInvisibly(_scaleStateFor(_desiredScale));
    return controller;
  }

  Size? _contentSizeForPage(int pageIndex) {
    final List<int> images = computeImagesInPageIndex(pageIndex);
    if (images.isEmpty) {
      return null;
    }

    double width = 0;
    double height = 0;
    for (final int imageIndex in images) {
      final Size? size = readPageState.imageContainerSizes[imageIndex];
      if (size == null) {
        return null;
      }
      width += size.width;
      height = max(height, size.height);
    }

    if (images.length > 1) {
      width += readSetting.imageSpace.value;
    }

    return Size(width, height);
  }

  @override
  Future<void> onInit() async {
    super.onInit();

    String? cacheString = await localConfigService.read(
      configKey: ConfigEnum.isSpreadPage,
      subConfigKey: readPageState.readPageInfo.readProgressRecordStorageKey,
    );
    if (cacheString == null) {
      state.isSpreadPage = List.generate(readPageState.readPageInfo.pageCount, (_) => false);
    } else {
      List list = jsonDecode(cacheString);
      state.isSpreadPage = list.map((e) => e == 1).toList();
    }
    state.isSpreadPageCompleter.complete();

    state.pageCount = computePageCount();

    state.pageController = PageController(initialPage: computePageIndexOfImage(readPageState.readPageInfo.initialIndex));

    /// record reading progress and sync thumbnails list index
    state.pageController.addListener(_readProgressListener);

    initCompleter.complete();
  }

  @override
  void toLeft() {
    if (readPageLogic.isInRight2LeftDirection) {
      toNext();
    } else {
      toPrev();
    }
  }

  @override
  void toRight() {
    if (readPageLogic.isInRight2LeftDirection) {
      toPrev();
    } else {
      toNext();
    }
  }

  @override
  void toPrev() {
    int currentPage = state.pageController.page!.toInt();
    if (currentPage <= 0) {
      return;
    }

    int targetIndex = computeImagesInPageIndex(currentPage - 1).first;
    toImageIndex(targetIndex);
  }

  @override
  void toNext() {
    int currentPage = state.pageController.page!.toInt();
    if (currentPage >= state.pageCount - 1) {
      return;
    }

    int targetIndex = computeImagesInPageIndex(currentPage + 1).first;
    toImageIndex(targetIndex);
  }

  @override
  Future<void> jump2ImageIndex(int imageIndex) async {
    await state.isSpreadPageCompleter.future;

    final int pageIndex = computePageIndexOfImage(imageIndex);

    /// seed the target page before the PageView jumps to it
    _preparePage(pageIndex);
    state.pageController.jumpToPage(pageIndex);
    super.jump2ImageIndex(imageIndex);
  }

  @override
  Future<void> scroll2ImageIndex(int imageIndex, [Duration? duration]) async {
    await state.isSpreadPageCompleter.future;

    final int pageIndex = computePageIndexOfImage(imageIndex);

    /// the page slides in already zoomed
    _preparePage(pageIndex);
    state.pageController.animateToPage(
      pageIndex,
      duration: duration ?? const Duration(milliseconds: 200),
      curve: Curves.ease,
    );
    super.scroll2ImageIndex(imageIndex, duration);
  }

  @override
  Future<void> toggleDisplayFirstPageAlone() async {
    await state.isSpreadPageCompleter.future;

    state.pageCount = computePageCount();
    updateSafely([BaseLayoutLogic.pageId]);
  }

  @override
  void enterAutoMode() {
    _enterAutoModeByTurnPage();
  }

  void _enterAutoModeByTurnPage() {
    readPageLogic.toggleMenu();

    autoModeTimer = Timer.periodic(
      Duration(milliseconds: (readSetting.autoModeInterval.value * 1000).toInt()),
      (_) {
        /// changed read direction
        if (!readPageLogic.isInDoubleColumnReadDirection) {
          Get.engine.addPostFrameCallback((_) {
            readPageLogic.closeAutoMode();
          });
          autoModeTimer?.cancel();
          return;
        }

        /// stop when at last
        if (state.pageController.page!.toInt() == state.pageCount - 1) {
          Get.engine.addPostFrameCallback((_) {
            readPageLogic.closeAutoMode();
          });
          autoModeTimer?.cancel();
          return;
        }

        toNext();
      },
    );
  }

  void _readProgressListener() {
    if (!state.pageController.hasClients || state.pageController.page == null) {
      return;
    }

    int currentPage = state.pageController.page!.toInt();
    List<int> imageIndexes = computeImagesInPageIndex(currentPage);
    if (imageIndexes.isEmpty) {
      return;
    }

    readPageLogic.recordReadProgress(imageIndexes.first);
    readPageLogic.syncThumbnails(imageIndexes.first);

    /// `round()` flips as soon as the incoming page covers half of the viewport
    /// (during swipes too), instead of only at the end of the animation.
    final int nearestPage = state.pageController.page!.round().clamp(0, state.pageCount - 1).toInt();

    if (nearestPage == _lastPage) {
      return;
    }

    final int? previousPage = _lastPage >= 0 ? _lastPage : null;
    _lastPage = nearestPage;
    _carryZoomFrom(previousPage);
    _preparePage(nearestPage);
  }

  /// Keeps the zoom level of the page the reader is leaving.
  void _carryZoomFrom(int? previousPage) {
    if (previousPage == null) {
      return;
    }
    final double? scale = state.photoViewControllers[previousPage]?.scale;
    if (scale != null) {
      _desiredScale = scale;
    }
  }

  /// Applies the session zoom to [pageIndex] and aligns the page to the top.
  void _preparePage(int pageIndex) {
    if (!initCompleter.isCompleted || pageIndex < 0 || pageIndex >= state.pageCount) {
      return;
    }

    final PhotoViewController controller = pageViewControllerFor(pageIndex);
    final PhotoViewScaleStateController scaleStateController = scaleStateControllerFor(pageIndex);
    final double scale = _desiredScale;
    final Size? contentSize = _contentSizeForPage(pageIndex);

    /// a spread page may still be missing one of its image sizes; the exact
    /// alignment is applied by [onImageSizeKnown] when the image loads.
    _pendingTopAlignPage = readSetting.alignToTopWhenTurnPage.isTrue && scale > BaseLayoutLogic.maxZoomScaleEpsilon && contentSize == null ? pageIndex : null;

    _applyZoomTo(controller, scale, contentSize);
    scaleStateController.setInvisibly(_scaleStateFor(scale));
  }

  /// Keeps the preloaded neighbours at the current zoom, so a swipe reveals an
  /// already zoomed page instead of popping from 1.0 at half of the viewport.
  void _syncNeighborZoom() {
    if (!initCompleter.isCompleted) {
      return;
    }

    final int current = currentPageIndex;
    for (final int pageIndex in <int>[current - 1, current + 1]) {
      if (pageIndex < 0 || pageIndex >= state.pageCount) {
        continue;
      }

      final PhotoViewController? controller = state.photoViewControllers[pageIndex];
      if (controller == null) {
        /// a page created later already uses the current zoom
        continue;
      }

      _applyZoomTo(controller, _desiredScale, _contentSizeForPage(pageIndex));
      state.photoViewScaleStateControllers[pageIndex]?.setInvisibly(_scaleStateFor(_desiredScale));
    }
  }

  void _applyZoomTo(PhotoViewController controller, double scale, Size? contentSize) {
    if (readSetting.alignToTopWhenTurnPage.isTrue) {
      controller.updateMultiple(
        scale: scale,
        position: scale > BaseLayoutLogic.maxZoomScaleEpsilon ? computeTopAlignedPosition(scale, contentSize) : Offset.zero,
      );
    } else {
      /// keep the pan of a page that was already visited
      controller.updateMultiple(scale: scale);
    }
  }

  Offset _initialPositionFor(int pageIndex) {
    final double scale = _desiredScale;
    if (scale <= BaseLayoutLogic.maxZoomScaleEpsilon || readSetting.alignToTopWhenTurnPage.isFalse || !initCompleter.isCompleted) {
      return Offset.zero;
    }
    return computeTopAlignedPosition(scale, _contentSizeForPage(pageIndex));
  }

  PhotoViewScaleState _scaleStateFor(double scale) =>
      scale > BaseLayoutLogic.maxZoomScaleEpsilon ? PhotoViewScaleState.zoomedIn : PhotoViewScaleState.initial;

  /// Tracks the zoom gestures of the current page so the next page is seeded
  /// with the scale the user actually chose.
  void _trackZoomOf(int pageIndex, PhotoViewController controller) {
    controller.outputStateStream.listen((PhotoViewControllerValue value) {
      if (pageIndex != currentPageIndex) {
        return;
      }
      final double? scale = value.scale;
      if (scale == null || (scale - _desiredScale).abs() < BaseLayoutLogic.maxZoomScaleEpsilon) {
        return;
      }
      _desiredScale = scale;
      _syncNeighborZoom();
    });
  }

  /// Re-aligns the zoomed page when the viewport changed (window resize,
  /// immersive mode switch). Called from the layout build.
  void onViewportChanged(Size size) {
    if (_lastViewportSize == size) {
      return;
    }
    _lastViewportSize = size;

    if (readSetting.alignToTopWhenTurnPage.isFalse) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isZoomed) {
        alignActiveContentToTop();
      }
    });
  }

  @override
  void onImageSizeKnown(int imageIndex) {
    final int? pendingPage = _pendingTopAlignPage;
    if (pendingPage == null || pendingPage != currentPageIndex) {
      return;
    }

    final Size? contentSize = _contentSizeForPage(pendingPage);
    if (contentSize == null) {
      return;
    }

    _pendingTopAlignPage = null;
    final double scale = _desiredScale;
    if (scale <= BaseLayoutLogic.maxZoomScaleEpsilon) {
      return;
    }

    state.photoViewControllers[pendingPage]?.updateMultiple(
      scale: scale,
      position: computeTopAlignedPosition(scale, contentSize),
    );
  }

  @override
  Size getPlaceHolderSize(int imageIndex) {
    if (readPageState.imageContainerSizes[imageIndex] != null) {
      return readPageState.imageContainerSizes[imageIndex]!;
    }
    return Size((fullScreenWidth - readSetting.imageSpace.value) / 2, double.infinity);
  }

  FittedSizes getImageFittedSizeIncludeSpread(Size imageSize, bool isSpreadPage) {
    return applyBoxFit(
      BoxFit.contain,
      Size(imageSize.width, imageSize.height),
      Size(
        isSpreadPage ? readPageState.displayRegionSize.width : (readPageState.displayRegionSize.width - readSetting.imageSpace.value) / 2,
        readPageState.displayRegionSize.height,
      ),
    );
  }

  Future<void> updateSpreadPage(int imageIndex) async {
    await state.isSpreadPageCompleter.future;

    /// has recognized from cache
    if (state.isSpreadPage[imageIndex]) {
      galleryDownloadService.updateSafely(['${galleryDownloadService.downloadImageId}::${readPageState.readPageInfo.gid}::$imageIndex']);
      return;
    }

    state.isSpreadPage[imageIndex] = true;
    state.pageCount = computePageCount();

    updateSafely([BaseLayoutLogic.pageId]);
    if (computePageIndexOfImage(imageIndex) <= state.pageController.page!.toInt()) {
      jump2ImageIndex(readPageState.readPageInfo.currentImageIndex);
    }

    await localConfigService.write(
      configKey: ConfigEnum.isSpreadPage,
      subConfigKey: readPageState.readPageInfo.gid.toString(),
      value: jsonEncode(state.isSpreadPage.map((e) => e ? 1 : 0).toList()),
    );
  }

  int computePageCount() {
    return computePageIndexOfImage(state.isSpreadPage.length - 1) + 1;
  }

  /// provide a page index, compute which images we should display in this page
  List<int> computeImagesInPageIndex(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= state.pageCount) {
      return [];
    }

    int currentImageIndex = 0;
    int currentPageIndex = 0;
    bool hasLeftColumn = false;
    /// Extends displayFirstPageAlone to apply after each spread, not just the cover.
    bool nextIsAlone = readPageState.displayFirstPageAlone;

    while (currentPageIndex < pageIndex) {
      bool isSpreadPage = state.isSpreadPage[currentImageIndex];

      if (isSpreadPage && !hasLeftColumn) {
        currentImageIndex++;
        currentPageIndex++;
        nextIsAlone = readPageState.displayFirstPageAlone;
        continue;
      }

      if (isSpreadPage && hasLeftColumn) {
        currentImageIndex++;
        currentPageIndex += 2;
        hasLeftColumn = false;
        nextIsAlone = readPageState.displayFirstPageAlone;
        continue;
      }

      if (nextIsAlone && !hasLeftColumn) {
        currentImageIndex++;
        currentPageIndex++;
        nextIsAlone = false;
        continue;
      }

      if (hasLeftColumn) {
        currentImageIndex++;
        currentPageIndex++;
        hasLeftColumn = false;
        continue;
      }

      currentImageIndex++;
      hasLeftColumn = true;
    }

    if (currentPageIndex > pageIndex) {
      return [currentImageIndex - 1];
    }

    if (state.isSpreadPage[currentImageIndex]) {
      return [currentImageIndex];
    }

    if (currentImageIndex == state.isSpreadPage.length - 1) {
      return [currentImageIndex];
    }

    if (state.isSpreadPage[currentImageIndex + 1]) {
      return [currentImageIndex];
    }

    if (nextIsAlone && !hasLeftColumn) {
      return [currentImageIndex];
    }

    return [currentImageIndex, currentImageIndex + 1];
  }

  /// provide a image index, compute we should display this image in which page
  int computePageIndexOfImage(int imageIndex) {
    int currentImageIndex = 0;
    int pageIndex = 0;
    bool hasLeftColumn = false;
    bool nextIsAlone = readPageState.displayFirstPageAlone;

    while (currentImageIndex < imageIndex) {
      bool isSpreadPage = state.isSpreadPage[currentImageIndex];

      if (isSpreadPage && !hasLeftColumn) {
        currentImageIndex++;
        pageIndex++;
        nextIsAlone = readPageState.displayFirstPageAlone;
        continue;
      }

      if (isSpreadPage && hasLeftColumn) {
        currentImageIndex++;
        pageIndex += 2;
        hasLeftColumn = false;
        nextIsAlone = readPageState.displayFirstPageAlone;
        continue;
      }

      if (nextIsAlone && !hasLeftColumn) {
        currentImageIndex++;
        pageIndex++;
        nextIsAlone = false;
        continue;
      }

      if (hasLeftColumn) {
        currentImageIndex++;
        pageIndex++;
        hasLeftColumn = false;
        continue;
      }

      currentImageIndex++;
      hasLeftColumn = true;
    }

    if (state.isSpreadPage[imageIndex] && hasLeftColumn) {
      return pageIndex + 1;
    }

    return pageIndex;
  }
}
