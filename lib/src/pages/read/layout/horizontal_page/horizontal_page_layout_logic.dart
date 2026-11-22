import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';
import 'package:photo_view/photo_view.dart';

import '../../spread_pages.dart';
import '../base/base_layout_logic.dart';
import 'horizontal_page_layout_state.dart';

class HorizontalPageLayoutLogic extends BaseLayoutLogic {
  HorizontalPageLayoutState state = HorizontalPageLayoutState();

  late PageController pageController;

  int _lastPage = -1;

  /// Zoom level of the reading session. Every page is shown at this scale, so
  /// turning a page never changes the zoom and a page is never painted at 1.0
  /// before being zoomed.
  double _desiredScale = 1.0;

  /// Zoom level [ _syncNeighborZoom] was last run at, so a pinch that fires
  /// dozens of scale events per second rebuilds the neighbour pages only when
  /// the scale actually moved (2%).
  double _lastNeighborZoomSync = 1.0;

  /// Page whose top alignment still has to be applied once its real content
  /// size is known.
  int? _pendingTopAlignPage;

  Size? _lastViewportSize;

  PageParts get pageParts => readSetting.splitWidePages.isTrue
      ? PageParts(readPageState.spreadPages.flags)
      : PageParts.unsplit(readPageState.readPageInfo.pageCount);

  int get currentPageIndex {
    final PageParts parts = pageParts;
    final int fallback = parts.firstPageOf(readPageState.readPageInfo.currentImageIndex);
    final int index = pageController.hasClients && pageController.page != null ? pageController.page!.round() : fallback;
    return index.clamp(0, max(0, parts.pageCount - 1)).toInt();
  }

  @override
  PhotoViewControllerBase? get activePhotoViewController => pageViewControllerFor(currentPageIndex);

  @override
  Size? get activeContentSize => readPageState.imageContainerSizes[pageParts.imageOf(currentPageIndex)];

  @override
  PhotoViewControllerBase? photoViewControllerForPlaceholder(int imageIndex) =>
      pageViewControllerFor(pageParts.firstPageOf(imageIndex));

  /// Controller of [pageIndex], created with the zoom of the reading session
  /// already applied.
  ///
  /// `photo_view` only figures the initial scale out of the scale state when the
  /// controller has no scale yet (see the vendored package), so seeding the
  /// controller here makes the page start zoomed and top aligned on its very
  /// first frame.
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

  @override
  void onInit() {
    super.onInit();

    final int initialPage = pageParts.firstPageOf(readPageState.readPageInfo.currentImageIndex);
    pageController = PageController(initialPage: initialPage);

    /// record reading progress and sync thumbnails list index
    pageController.addListener(_readProgressListener);

    /// the initial page is built before any turn happens, so apply the session
    /// zoom to it here as well
    _preparePage(initialPage);
  }

  /// Ensures returning to paged layout from a scrolling layout lands on the
  /// exact image the user scrolled to instead of the controller's stale initial
  /// page.
  void syncToCurrentImageIndex() {
    final PageParts parts = pageParts;
    final int target = parts.firstPageOf(readPageState.readPageInfo.currentImageIndex)
        .clamp(0, max(0, parts.pageCount - 1))
        .toInt();
    if (!pageController.hasClients) {
      if (pageController.initialPage != target) {
        pageController.removeListener(_readProgressListener);
        pageController.dispose();
        pageController = PageController(initialPage: target);
        pageController.addListener(_readProgressListener);
        _lastPage = -1;
        _preparePage(target);
      }
    }
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
    if (!pageController.hasClients || pageController.page == null) {
      return;
    }
    final int targetPage = max(pageController.page!.round() - 1, 0);
    _goToPage(targetPage);
  }

  @override
  void toNext() {
    if (!pageController.hasClients || pageController.page == null) {
      return;
    }
    final int targetPage = min(pageController.page!.round() + 1, max(0, pageParts.pageCount - 1));
    _goToPage(targetPage);
  }

  void _goToPage(int targetPage) {
    _preparePage(targetPage);
    if (readSetting.enablePageTurnAnime.isTrue) {
      pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 200),
        curve: Curves.ease,
      );
    } else {
      pageController.jumpToPage(targetPage);
    }
  }

  @override
  void jump2ImageIndex(int imageIndex) {
    final int targetPage = pageParts.firstPageOf(imageIndex);
    /// seed the target page before the PageView jumps to it, so its first frame
    /// is already zoomed and top aligned
    _preparePage(targetPage);
    pageController.jumpToPage(targetPage);
    super.jump2ImageIndex(imageIndex);
  }

  @override
  void scroll2ImageIndex(int imageIndex, [Duration? duration]) {
    final int targetPage = pageParts.firstPageOf(imageIndex);
    /// same as [jump2ImageIndex]: the page slides in already zoomed
    _preparePage(targetPage);
    pageController.animateToPage(
      targetPage,
      duration: duration ?? const Duration(milliseconds: 200),
      curve: Curves.ease,
    );
    super.scroll2ImageIndex(imageIndex, duration);
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
        /// changed read setting
        if (!readPageLogic.isInSinglePageReadDirection) {
          Get.engine.addPostFrameCallback((_) {
            readPageLogic.closeAutoMode();
          });
          autoModeTimer?.cancel();
          return;
        }

        /// stop when at last
        if (readPageState.readPageInfo.currentImageIndex == readPageState.readPageInfo.pageCount - 1) {
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

    final int pendingImage = pageParts.imageOf(pendingPage);
    if (pendingImage != imageIndex) {
      return;
    }

    final Size? contentSize = readPageState.imageContainerSizes[pendingImage];
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

  void _readProgressListener() {
    if (!pageController.hasClients || pageController.page == null) {
      return;
    }

    final PageParts parts = pageParts;
    final int currentPage = pageController.page!.toInt().clamp(0, max(0, parts.pageCount - 1)).toInt();
    final int currentImage = parts.imageOf(currentPage);
    readPageLogic.recordReadProgress(currentImage);
    readPageLogic.syncThumbnails(currentImage);

    /// `round()` flips as soon as the incoming page covers half of the viewport
    /// (during swipes too), instead of only at the end of the animation.
    final int nearestPage = pageController.page!.round().clamp(0, max(0, parts.pageCount - 1)).toInt();

    if (nearestPage == _lastPage) {
      return;
    }

    final int? previousPage = _lastPage >= 0 ? _lastPage : null;
    _lastPage = nearestPage;
    _carryZoomFrom(previousPage);
    _preparePage(nearestPage);
    _resetFitWidthScroll(nearestPage);
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

  /// Applies the session zoom to [pageIndex] and aligns it to the top.
  ///
  /// Called before the page becomes visible (programmatic turns) and as soon as
  /// the incoming page covers half of the viewport (swipes).
  void _preparePage(int pageIndex) {
    final PageParts parts = pageParts;
    if (pageIndex < 0 || pageIndex >= parts.pageCount) {
      return;
    }

    final PhotoViewController controller = pageViewControllerFor(pageIndex);
    final PhotoViewScaleStateController scaleStateController = scaleStateControllerFor(pageIndex);
    final double scale = _desiredScale;
    final Size? contentSize = readPageState.imageContainerSizes[parts.imageOf(pageIndex)];

    /// without the real content size the position is a viewport based guess;
    /// [onImageSizeKnown] applies the exact one when the image loads.
    _pendingTopAlignPage = readSetting.alignToTopWhenTurnPage.isTrue && scale > BaseLayoutLogic.maxZoomScaleEpsilon && contentSize == null ? pageIndex : null;

    _applyZoomTo(controller, scale, contentSize);
    scaleStateController.setInvisibly(_scaleStateFor(scale));
  }

  /// Keeps the preloaded neighbours at the current zoom, so a swipe reveals an
  /// already zoomed page instead of popping from 1.0 when it reaches half of the
  /// viewport.
  void _syncNeighborZoom() {
    final PageParts parts = pageParts;
    final int current = currentPageIndex;
    for (final int pageIndex in <int>[current - 1, current + 1]) {
      if (pageIndex < 0 || pageIndex >= parts.pageCount) {
        continue;
      }

      final PhotoViewController? controller = state.photoViewControllers[pageIndex];
      if (controller == null) {
        /// a page created later already uses the current zoom
        continue;
      }

      _applyZoomTo(controller, _desiredScale, readPageState.imageContainerSizes[parts.imageOf(pageIndex)]);
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
    if (scale <= BaseLayoutLogic.maxZoomScaleEpsilon || readSetting.alignToTopWhenTurnPage.isFalse) {
      return Offset.zero;
    }
    return computeTopAlignedPosition(scale, readPageState.imageContainerSizes[pageParts.imageOf(pageIndex)]);
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
      if ((scale - _lastNeighborZoomSync).abs() >= 0.02) {
        _lastNeighborZoomSync = scale;
        _syncNeighborZoom();
      }
    });
  }

  void _resetFitWidthScroll(int pageIndex) {
    if (!readPageLogic.isInFitWidthReadDirection) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ScrollController scrollController = state.scrollControllerOf(pageIndex);
      if (scrollController.hasClients) {
        scrollController.jumpTo(0);
      }
    });
  }
}
