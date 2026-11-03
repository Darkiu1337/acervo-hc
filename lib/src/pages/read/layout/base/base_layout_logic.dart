import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:clipboard/clipboard.dart';
import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_instance/get_instance.dart';
import 'package:get/get_navigation/get_navigation.dart';
import 'package:get/get_rx/get_rx.dart';
import 'package:get/get_state_manager/get_state_manager.dart';
import 'package:get/get_utils/get_utils.dart';
import 'package:acervo_hc/src/consts/eh_consts.dart';
import 'package:acervo_hc/src/extension/get_logic_extension.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/network/eh_request.dart';
import 'package:acervo_hc/src/service/gallery_download/download_path_resolver.dart';
import 'package:acervo_hc/src/service/gallery_download/eh_image_exception_matcher.dart';
import 'package:acervo_hc/src/service/gallery_download/gallery_download_service.dart';
import 'package:acervo_hc/src/service/external_viewer_service.dart';
import 'package:acervo_hc/src/service/path_service.dart';
import 'package:acervo_hc/src/setting/download_setting.dart';
import 'package:acervo_hc/src/setting/style_setting.dart';
import 'package:acervo_hc/src/setting/user_setting.dart';
import 'package:acervo_hc/src/utils/permission_util.dart';
import 'package:acervo_hc/src/utils/string_uril.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/eh_action_sheet_text.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../exception/eh_image_exception.dart';
import '../../../../model/gallery_image.dart';
import '../../../../model/read_page_info.dart';
import '../../../../service/log.dart';
import '../../../../setting/read_setting.dart';
import '../../../../utils/route_util.dart';
import '../../../../utils/screen_size_util.dart';
import '../../read_page_logic.dart';
import '../../read_page_state.dart';

abstract class BaseLayoutLogic extends GetxController with GetTickerProviderStateMixin {
  static const String pageId = 'pageId';

  final ReadPageLogic readPageLogic = Get.find<ReadPageLogic>();
  final ReadPageState readPageState = Get.find<ReadPageLogic>().state;

  Timer? autoModeTimer;
  Timer? alignToTopTimer;
  Worker? doubleTapGestureSwitcherListener;
  Worker? tapDragGestureSwitcherListener;
  Worker? showScrollBarListener;
  Worker? upscaleListener;
  Worker? zoomStepListener;

  @override
  void onInit() {
    doubleTapGestureSwitcherListener = ever(readSetting.enableDoubleTapToScaleUp, (value) => updateSafely([pageId]));
    tapDragGestureSwitcherListener = ever(readSetting.enableTapDragToScaleUp, (value) => updateSafely([pageId]));
    showScrollBarListener = ever(readSetting.showScrollBar, (value) => updateSafely([pageId]));
    upscaleListener = ever(readSetting.enableUpscale, (value) => updateSafely([pageId]));
    zoomStepListener = ever(readSetting.zoomStepPercent, (value) => updateSafely([pageId]));
    super.onInit();
  }

  @override
  void onClose() {
    autoModeTimer?.cancel();
    alignToTopTimer?.cancel();
    doubleTapGestureSwitcherListener?.dispose();
    tapDragGestureSwitcherListener?.dispose();
    showScrollBarListener?.dispose();
    upscaleListener?.dispose();
    zoomStepListener?.dispose();
    super.onClose();
  }

  /// Tap left region or click right arrow key. If read direction is right-to-left, we should call [toNext], otherwise [toPrev]
  void toLeft();

  /// Tap right region or click right arrow key. If read direction is right-to-left, we should call [toPrev], otherwise [toNext]
  void toRight();

  /// to prev image or screen
  void toPrev();

  /// to next image or screen
  void toNext();

  void toImageIndex(int imageIndex) {
    if (readSetting.enablePageTurnAnime.isFalse) {
      jump2ImageIndex(imageIndex);
    } else {
      scroll2ImageIndex(imageIndex);
    }
  }

  @mustCallSuper
  void scroll2ImageIndex(int imageIndex, [Duration? duration]) {
    readPageLogic.update([readPageLogic.sliderId]);
  }

  @mustCallSuper
  void jump2ImageIndex(int imageIndex) {
    readPageLogic.syncThumbnails(imageIndex);
    readPageLogic.update([readPageLogic.sliderId]);
  }

  PhotoViewScaleState scaleStateCycle(PhotoViewScaleState actual) {
    switch (actual) {
      case PhotoViewScaleState.initial:
        return PhotoViewScaleState.zoomedIn;
      default:
        return PhotoViewScaleState.initial;
    }
  }

  /// Controller of the content currently visible in the viewport.
  ///
  /// Page layouts return the controller of the current page, list layouts
  /// return their single controller.
  PhotoViewControllerBase? get activePhotoViewController => null;

  /// Size of the visible content at scale 1.0, when the layout can compute it.
  Size? get activeContentSize => null;

  /// Controller of the page that owns [imageIndex], used to keep loading and
  /// error placeholders unzoomed.
  ///
  /// List layouts return null: their PhotoView child is the whole list, not a
  /// viewport sized page, so the inverse transform used for placeholders does
  /// not apply there.
  PhotoViewControllerBase? photoViewControllerForPlaceholder(int imageIndex) => null;

  double get activeScale => activePhotoViewController?.scale ?? 1.0;

  bool get isZoomed => activeScale > maxZoomScaleEpsilon;

  /// Upper zoom bound used by every reading layout.
  static const double maxZoomScale = 2.5;

  /// Minimum difference that is still considered a zoom change.
  static const double maxZoomScaleEpsilon = 0.001;

  /// Percentage of the viewport covered by one arrow-key pan.
  static const double _panViewportRatio = 0.08;

  bool get isCtrlPressed {
    final Set<LogicalKeyboardKey> pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.controlLeft) || pressed.contains(LogicalKeyboardKey.controlRight);
  }

  /// Distance covered by one arrow-key pan, proportional to the viewport.
  Offset get panStep {
    final Size region = readPageState.displayRegionSize;
    return Offset(region.width * _panViewportRatio, region.height * _panViewportRatio);
  }

  /// Allowed position range for [scale], derived from the real content size.
  ///
  /// photo_view only knows the viewport as its child size (no page passes
  /// `childSize`), so its own clamp lets the image be dragged past its edges.
  /// When the layout knows the content size, panning is bounded by it instead.
  Offset? computePanBounds(double scale) {
    final Size? contentSize = activeContentSize;
    if (contentSize == null || scale <= maxZoomScaleEpsilon) {
      return null;
    }

    final Size viewport = readPageState.displayRegionSize;
    return Offset(
      max(0.0, (contentSize.width * scale - viewport.width) / 2),
      max(0.0, (contentSize.height * scale - viewport.height) / 2),
    );
  }

  Offset clampPanPosition(Offset position, double scale) {
    final Offset? bounds = computePanBounds(scale);
    if (bounds == null) {
      return position;
    }
    return Offset(
      position.dx.clamp(-bounds.dx, bounds.dx).toDouble(),
      position.dy.clamp(-bounds.dy, bounds.dy).toDouble(),
    );
  }

  void panBy(Offset delta) {
    final PhotoViewControllerBase? controller = activePhotoViewController;
    if (controller == null) {
      return;
    }

    final double scale = controller.scale ?? 1.0;
    controller.updateMultiple(position: clampPanPosition(controller.position + delta, scale));
  }

  void panUp() => panBy(Offset(0, panStep.dy));

  void panDown() => panBy(Offset(0, -panStep.dy));

  /// Ctrl+Left: reveal the left side of the zoomed content.
  void panLeft() => panBy(Offset(panStep.dx, 0));

  /// Ctrl+Right: reveal the right side of the zoomed content.
  void panRight() => panBy(Offset(-panStep.dx, 0));

  /// Zoom step used by ctrl+wheel and by the +/- keys, as a fraction (0.08 =
  /// 8% per step).
  double get zoomStep => (readSetting.zoomStepPercent.value / 100).clamp(0.01, 0.5).toDouble();

  void zoomIn() => zoomBy(1 + zoomStep);

  void zoomOut() => zoomBy(1 - zoomStep);

  /// Multiplies the current scale by [factor] without moving the position, so
  /// the point in the center of the viewport stays put. photo_view clamps the
  /// position when the resulting scale is applied.
  void zoomBy(double factor) {
    final PhotoViewControllerBase? controller = activePhotoViewController;
    if (controller == null) {
      return;
    }

    final double currentScale = controller.scale ?? 1.0;
    final double nextScale = (currentScale * factor).clamp(1.0, maxZoomScale).toDouble();
    if ((nextScale - currentScale).abs() < maxZoomScaleEpsilon) {
      return;
    }

    controller.updateMultiple(scale: nextScale, position: clampPanPosition(controller.position, nextScale));
  }

  /// Position that puts the top edge of the visible content at the top of the
  /// viewport without changing the current scale.
  ///
  /// photo_view scales around the center and then applies the controller
  /// position as a screen-space translation, so a positive Y moves the content
  /// down.
  Offset computeTopAlignedPosition(double scale, Size? contentSize) {
    final Size viewport = readPageState.displayRegionSize;
    final double contentHeight = contentSize?.height ?? viewport.height;
    return Offset(0, max(0.0, (contentHeight * scale - viewport.height) / 2));
  }

  /// Re-applies the current scale while moving the content back to its top
  /// edge. When not zoomed, the default centered position is restored.
  void alignActiveContentToTop() {
    final PhotoViewControllerBase? controller = activePhotoViewController;
    if (controller == null) {
      return;
    }

    final double scale = controller.scale ?? 1.0;
    final Offset position = scale > maxZoomScaleEpsilon ? computeTopAlignedPosition(scale, activeContentSize) : Offset.zero;
    controller.updateMultiple(position: position, scale: scale);
  }

  /// Called when the real size of an image becomes known (right after
  /// `imageContainerSizes[index]` is filled).
  ///
  /// Layouts that align new pages to the top use it to correct the alignment
  /// when the size was still unknown during the page change.
  void onImageSizeKnown(int imageIndex) {}

  /// Aligns the zoomed content to the top immediately, honouring the user
  /// setting. Used by the list layouts, where the alignment does not depend on
  /// the item size and can be applied before the scroll animation starts.
  void alignToTopIfNeeded() {
    if (readSetting.alignToTopWhenTurnPage.isFalse || !isZoomed) {
      return;
    }
    alignActiveContentToTop();
  }

  /// Debounced top alignment for scrolling layouts, where the visible image
  /// changes many times during a single gesture.
  void scheduleAlignToTop([Duration delay = const Duration(milliseconds: 200)]) {
    alignToTopTimer?.cancel();
    alignToTopTimer = Timer(delay, alignActiveContentToTop);
  }

  void toggleDisplayFirstPageAlone() {}

  void enterAutoMode();

  @mustCallSuper
  void closeAutoMode() {
    autoModeTimer?.cancel();
  }

  void onPointerScroll(PointerScrollEvent value) {
    if (isCtrlPressed) {
      return;
    }

    if (value.scrollDelta.dy > 0) {
      toNext();
    } else if (value.scrollDelta.dy < 0) {
      toPrev();
    }
  }

  /// Unified entry point for online image context menus.
  /// Dispatches to [showOnlineDesktopContextMenu] on desktop or [showOnlineMobileBottomMenu] on mobile.
  void showOnlineImageContextMenu(int index, BuildContext context, {Offset? position}) {
    if (styleSetting.isInDesktopLayout && position != null) {
      showOnlineDesktopContextMenu(index: index, context: context, position: position);
    } else {
      showOnlineMobileBottomMenu(index, context);
    }
  }

  /// Whether the "open in external viewer" action is available.
  ///
  /// The custom viewer path is configured in Settings > Read for desktop
  /// platforms only; the switch that redirects downloaded galleries to the
  /// viewer is intentionally not required, since it is usually off for people
  /// who read inside Acervo H&C.
  bool get showExternalViewerAction => GetPlatform.isDesktop && (readSetting.thirdPartyViewerPath.value?.trim().isNotEmpty ?? false);

  /// Opens the gallery in the external image viewer configured in
  /// Settings > Read.
  ///
  /// Online galleries are streamed page by page into a temporary folder (or
  /// fully downloaded first, depending on the configured mode). Already
  /// downloaded/archive/local galleries open the current image file directly.
  Future<void> openInExternalViewer(int index) async {
    if (readPageState.readPageInfo.mode == ReadMode.online) {
      await externalViewerService.openOnlineGallery(
        readPageInfo: readPageState.readPageInfo,
        startIndex: index,
        resolveImage: (i) => readPageLogic.resolveImageForExternalViewer(i),
      );
      return;
    }

    String? target;
    switch (readPageState.readPageInfo.mode) {
      case ReadMode.downloaded:
        if (readPageState.images[index]?.path != null) {
          target = _getDownloadedImageAbsolutePath(index);
        }
        break;
      case ReadMode.archive:
        if (readPageState.images[index] != null) {
          target = _getArchiveImageAbsolutePath(index);
        }
        break;
      case ReadMode.local:
        target = readPageState.images[index]?.path;
        break;
      case ReadMode.online:
        break;
    }

    if (target == null || target.isEmpty) {
      toast('failed'.tr);
      return;
    }

    await externalViewerService.openLocalFile(target);
  }

  /// Desktop right-click context menu for online images.
  Future<void> showOnlineDesktopContextMenu({required int index, required BuildContext context, required Offset position}) async {
    final bool isEHSource = sourceOfGid(readPageState.readPageInfo.gid) == GallerySource.eh;
    final selected = await showMenu<String>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(value: 'reload', child: Text('reload'.tr)),
        PopupMenuItem(value: 'copyImage', child: Text('copyImage'.tr)),
        if (isEHSource) PopupMenuItem(value: 'copy_eh_page_url', child: Text('copyEHPageUrl'.tr)),
        if (showExternalViewerAction) PopupMenuItem(value: 'open_external_viewer', child: Text('openInExternalViewer'.tr)),
        PopupMenuItem(value: 'save', child: Text('${'save'.tr}(${'resampleImage'.tr})')),
        if (readPageState.images[index]!.originalImageUrl != null && userSetting.hasLoggedIn())
          PopupMenuItem(value: 'save_original', child: Text('${'save'.tr}(${'originalImage'.tr})')),
        PopupMenuItem(value: 'open_read_setting', child: Text('setting'.tr)),
      ],
    );

    switch (selected) {
      case 'reload':
        readPageLogic.reloadImage(index);
        break;
      case 'copyImage':
        copyOnlineImage(index);
        break;
      case 'copy_eh_page_url':
        copyEHPageUrl(index);
        break;
      case 'open_external_viewer':
        await openInExternalViewer(index);
        break;
      case 'save':
        await saveOnlineImage(index);
        break;
      case 'save_original':
        await saveOriginalOnlineImage(index);
        break;
      case 'open_read_setting':
        readPageLogic.openReadSetting(context);
        break;
    }
  }

  /// Mobile bottom action sheet for online images.
  void showOnlineMobileBottomMenu(int index, BuildContext context) {
    final bool isEHSource = sourceOfGid(readPageState.readPageInfo.gid) == GallerySource.eh;

    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            child: ehActionSheetText('reload'.tr),
            onPressed: () {
              backRoute();
              readPageLogic.reloadImage(index);
            },
          ),
          CupertinoActionSheetAction(
            child: ehActionSheetText('share'.tr),
            onPressed: () async {
              backRoute();
              shareOnlineImage(index);
            },
          ),
          CupertinoActionSheetAction(
            child: ehActionSheetText('copyImage'.tr),
            onPressed: () async {
              backRoute();
              copyOnlineImage(index);
            },
          ),
          if (isEHSource)
            CupertinoActionSheetAction(
              child: ehActionSheetText('copyEHPageUrl'.tr),
              onPressed: () async {
                backRoute();
                copyEHPageUrl(index);
              },
            ),
          if (showExternalViewerAction)
            CupertinoActionSheetAction(
              child: ehActionSheetText('openInExternalViewer'.tr),
              onPressed: () async {
                backRoute();
                await openInExternalViewer(index);
              },
            ),
          CupertinoActionSheetAction(
            child: ehActionSheetText('${'save'.tr}(${'resampleImage'.tr})'),
            onPressed: () async {
              backRoute();
              saveOnlineImage(index);
            },
          ),
          if (readPageState.images[index]!.originalImageUrl != null && userSetting.hasLoggedIn())
            CupertinoActionSheetAction(
              child: ehActionSheetText('${'save'.tr}(${'originalImage'.tr})'),
              onPressed: () async {
                backRoute();
                saveOriginalOnlineImage(index);
              },
            ),
        ],
        cancelButton: CupertinoActionSheetAction(child: ehActionSheetText('cancel'.tr), onPressed: backRoute),
      ),
    );
  }

  String _getDownloadedImageAbsolutePath(int index) {
    return DownloadPathResolver.computeImageDownloadAbsolutePathFromRelativePath(
      readPageState.images[index]!.path!,
    );
  }

  String _getArchiveImageAbsolutePath(int index) {
    return join(pathService.getVisibleDir().path, readPageState.images[index]!.path!);
  }

  /// Unified entry point for local image context menus.
  /// Handles [ReadMode.downloaded] and [ReadMode.archive].
  /// Dispatches to desktop context menus or mobile bottom sheets based on current layout.
  /// [ReadMode.online] images use [showOnlineImageContextMenu] instead.
  void showLocalImageContextMenu(int index, BuildContext context, {Offset? position}) {
    final mode = readPageState.readPageInfo.mode;
    if (mode == ReadMode.online || mode == ReadMode.local) {
      return;
    }

    final showDownloadedMenu = mode == ReadMode.downloaded;

    if (styleSetting.isInDesktopLayout && position != null) {
      if (showDownloadedMenu) {
        showDownloadedDesktopContextMenu(index: index, context: context, position: position);
      } else {
        showArchiveDesktopContextMenu(index: index, context: context, position: position);
      }
    } else {
      if (showDownloadedMenu) {
        showDownloadedMobileBottomMenu(index, context);
      } else {
        showArchiveMobileBottomMenu(index, context);
      }
    }
  }

  /// Mobile bottom action sheet for downloaded-mode images.
  void showDownloadedMobileBottomMenu(int index, BuildContext context) {
    if (galleryDownloadService.galleryDownloadInfos[readPageState.readPageInfo.gid]?.imageAtSync(index)?.downloadStatus != DownloadStatus.downloaded) {
      return;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            child: ehActionSheetText('share'.tr),
            onPressed: () {
              backRoute();
              shareDownloadedImageFile(index);
            },
          ),
          CupertinoActionSheetAction(
            child: ehActionSheetText('copyImage'.tr),
            onPressed: () {
              backRoute();
              copyDownloadedImageFile(index);
            },
          ),
          CupertinoActionSheetAction(
            child: ehActionSheetText('copyEHPageUrl'.tr),
            onPressed: () async {
              backRoute();
              copyEHPageUrl(index);
            },
          ),
          if (showExternalViewerAction)
            CupertinoActionSheetAction(
              child: ehActionSheetText('openInExternalViewer'.tr),
              onPressed: () async {
                backRoute();
                await openInExternalViewer(index);
              },
            ),
          CupertinoActionSheetAction(
            child: ehActionSheetText('save'.tr),
            onPressed: () {
              backRoute();
              saveDownloadedImageFile(index);
            },
          ),
          CupertinoActionSheetAction(
            child: ehActionSheetText('reDownload'.tr),
            onPressed: () {
              backRoute();
              galleryDownloadService.reDownloadImage(readPageState.readPageInfo.gid!, index);
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(child: ehActionSheetText('cancel'.tr), onPressed: backRoute),
      ),
    );
  }

  /// Mobile bottom action sheet for archive-mode images.
  void showArchiveMobileBottomMenu(int index, BuildContext context) {
    if (readPageState.images[index] == null) {
      return;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            child: ehActionSheetText('share'.tr),
            onPressed: () {
              backRoute();
              shareArchiveImageFile(index);
            },
          ),
          CupertinoActionSheetAction(
            child: ehActionSheetText('copyImage'.tr),
            onPressed: () {
              backRoute();
              copyArchiveImageFile(index);
            },
          ),
          if (showExternalViewerAction)
            CupertinoActionSheetAction(
              child: ehActionSheetText('openInExternalViewer'.tr),
              onPressed: () async {
                backRoute();
                await openInExternalViewer(index);
              },
            ),
          CupertinoActionSheetAction(
            child: ehActionSheetText('save'.tr),
            onPressed: () {
              backRoute();
              saveArchiveImageFile(index);
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(child: ehActionSheetText('cancel'.tr), onPressed: backRoute),
      ),
    );
  }

  /// Desktop right-click context menu for downloaded-mode images.
  Future<void> showDownloadedDesktopContextMenu({
    required int index,
    required BuildContext context,
    required Offset position,
  }) async {
    if (galleryDownloadService.galleryDownloadInfos[readPageState.readPageInfo.gid]?.imageAtSync(index)?.downloadStatus != DownloadStatus.downloaded) {
      return;
    }

    final selected = await showMenu<String>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(value: 'copyImage', child: Text('copyImage'.tr)),
        PopupMenuItem(value: 'copy_eh_page_url', child: Text('copyEHPageUrl'.tr)),
        if (showExternalViewerAction) PopupMenuItem(value: 'open_external_viewer', child: Text('openInExternalViewer'.tr)),
        PopupMenuItem(value: 'save', child: Text('save'.tr)),
        PopupMenuItem(value: 'redownload', child: Text('reDownload'.tr)),
        PopupMenuItem(value: 'open_read_setting', child: Text('setting'.tr)),
      ],
    );

    switch (selected) {
      case 'copyImage':
        copyDownloadedImageFile(index);
        break;
      case 'copy_eh_page_url':
        copyEHPageUrl(index);
        break;
      case 'open_external_viewer':
        await openInExternalViewer(index);
        break;
      case 'save':
        saveDownloadedImageFile(index);
        break;
      case 'redownload':
        galleryDownloadService.reDownloadImage(readPageState.readPageInfo.gid!, index);
        break;
      case 'open_read_setting':
        readPageLogic.openReadSetting(context);
        break;
    }
  }

  /// Desktop right-click context menu for archive-mode images.
  Future<void> showArchiveDesktopContextMenu({
    required int index,
    required BuildContext context,
    required Offset position,
  }) async {
    if (readPageState.images[index] == null) {
      return;
    }

    final selected = await showMenu<String>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(value: 'copyImage', child: Text('copyImage'.tr)),
        if (showExternalViewerAction) PopupMenuItem(value: 'open_external_viewer', child: Text('openInExternalViewer'.tr)),
        PopupMenuItem(value: 'save', child: Text('save'.tr)),
        PopupMenuItem(value: 'open_read_setting', child: Text('setting'.tr)),
      ],
    );

    switch (selected) {
      case 'copyImage':
        copyArchiveImageFile(index);
        break;
      case 'open_external_viewer':
        await openInExternalViewer(index);
        break;
      case 'save':
        saveArchiveImageFile(index);
        break;
      case 'open_read_setting':
        readPageLogic.openReadSetting(context);
        break;
    }
  }

  /// Share an online image via the system share sheet.
  Future<void> shareOnlineImage(int index) async {
    if (readPageState.images[index] == null) {
      return;
    }

    Uint8List? data = await getNetworkImageData(readPageState.images[index]!.url);
    if (data == null) {
      return;
    }

    String ext = extension(readPageState.images[index]!.url);
    if (isEmptyOrNull(ext)) {
      ext = basename(readPageState.images[index]!.url);
    }

    String fileName = '${readPageState.readPageInfo.gid!}_${readPageState.readPageInfo.token!}_$index$ext';

    Share.shareXFiles(
      [XFile.fromData(data)],
      sharePositionOrigin: Rect.fromLTWH(0, 0, fullScreenWidth, readPageState.displayRegionSize.height * 2 / 3),
      fileNameOverrides: [fileName],
    );
  }

  /// Share a downloaded-mode image file via the system share sheet.
  void shareDownloadedImageFile(int index) {
    Share.shareXFiles(
      [XFile(_getDownloadedImageAbsolutePath(index))],
      sharePositionOrigin: Rect.fromLTWH(0, 0, fullScreenWidth, readPageState.displayRegionSize.height * 2 / 3),
    );
  }

  /// Share an archive-mode image file via the system share sheet.
  void shareArchiveImageFile(int index) {
    Share.shareXFiles(
      [XFile(_getArchiveImageAbsolutePath(index))],
      sharePositionOrigin: Rect.fromLTWH(0, 0, fullScreenWidth, readPageState.displayRegionSize.height * 2 / 3),
    );
  }

  /// Copy an online image to clipboard.
  /// On desktop: writes image to temp file then uses [Pasteboard.writeFiles].
  /// On mobile: uses [Pasteboard.writeImage] with raw bytes.
  Future<void> copyOnlineImage(int index) async {
    if (readPageState.images[index] == null) {
      return;
    }

    Uint8List? data = await getNetworkImageData(readPageState.images[index]!.url);
    if (data == null) {
      return;
    }

    if (GetPlatform.isDesktop) {
      String ext = extension(readPageState.images[index]!.url);
      if (isEmptyOrNull(ext)) {
        ext = basename(readPageState.images[index]!.url);
      }
      String fileName = '${readPageState.readPageInfo.gid!}_${readPageState.readPageInfo.token!}_$index$ext';
      String filePath = join(downloadSetting.tempDownloadPath.value, fileName);
      File file = File(filePath);
      try {
        await file.create(recursive: true);
        await file.writeAsBytes(data);
        await Pasteboard.writeFiles([file.path]);
        toast('hasCopiedToClipboard'.tr);
      } catch (e) {
        log.error('Copy online image to clipboard failed: $e');
        toast('failed'.tr);
        file.delete().ignore();
      }
    } else {
      await Pasteboard.writeImage(data);
      toast('hasCopiedToClipboard'.tr);
    }
  }

  /// Copy a downloaded-mode image file to clipboard.
  void copyDownloadedImageFile(int index) {
    if (GetPlatform.isDesktop) {
      Pasteboard.writeFiles([_getDownloadedImageAbsolutePath(index)]).then((_) => toast('hasCopiedToClipboard'.tr));
    } else {
      Pasteboard.writeImage(File(_getDownloadedImageAbsolutePath(index)).readAsBytesSync()).then((_) => toast('hasCopiedToClipboard'.tr));
    }
  }

  /// Copy an archive-mode image file to clipboard.
  void copyArchiveImageFile(int index) {
    if (GetPlatform.isDesktop) {
      Pasteboard.writeFiles([_getArchiveImageAbsolutePath(index)]).then((_) => toast('hasCopiedToClipboard'.tr));
    } else {
      Pasteboard.writeImage(File(_getArchiveImageAbsolutePath(index)).readAsBytesSync()).then((_) => toast('hasCopiedToClipboard'.tr));
    }
  }

  Future<void> saveOnlineImage(int index) async {
    if (readPageState.images[index] == null) {
      return;
    }

    Uint8List? data = await getNetworkImageData(readPageState.images[index]!.url);
    if (data == null) {
      return;
    }

    // deal with .webp/.jpg which has not basename
    String ext = extension(readPageState.images[index]!.url);
    if (isEmptyOrNull(ext)) {
      ext = basename(readPageState.images[index]!.url);
    }

    String fileName = '${readPageState.readPageInfo.gid!}_${readPageState.readPageInfo.token!}_$index$ext';

    if (GetPlatform.isDesktop) {
      File file = File(join(downloadSetting.singleImageSavePath.value, fileName));
      try {
        await file.create(recursive: true);
        await file.writeAsBytes(data);
        toast('saveSuccess'.tr);
      } catch (e) {
        log.error('Save online image failed: $e');
        toast('saveFailed'.tr);
        file.delete().ignore();
        return;
      }
    } else {
      File file = File(join(downloadSetting.tempDownloadPath.value, fileName));
      try {
        await file.create(recursive: true);
        await file.writeAsBytes(data);
        bool success = await _saveFile2Album(file.path, fileName);
        toast(success ? 'saveSuccess'.tr : 'saveFailed'.tr);
      } catch (e) {
        log.error('Save online image failed: $e');
        toast('saveFailed'.tr);
        file.delete().ignore();
        return;
      }
    }
  }

  Future<void> saveOriginalOnlineImage(int index) async {
    if (readPageState.images[index] == null) {
      return;
    }

    if (readPageState.images[index]!.originalImageUrl == null || !userSetting.hasLoggedIn()) {
      return saveOnlineImage(index);
    }

    // deal with .webp/.jpg which has not basename
    String ext = extension(readPageState.images[index]!.originalImageUrl!);
    if (isEmptyOrNull(ext)) {
      ext = basename(readPageState.images[index]!.originalImageUrl!);
    }

    String fileName = '${readPageState.readPageInfo.gid!}_${readPageState.readPageInfo.token!}_${index}_original$ext';
    String downloadPath = join(downloadSetting.tempDownloadPath.value, fileName);
    File file = File(downloadPath);

    toast('downloading'.tr);
    Response response = await ehRequest.download(url: readPageState.images[index]!.originalImageUrl!, path: downloadPath);

    /// what we downloaded is not an image
    if (!response.isRedirect && (response.headers[Headers.contentTypeHeader]?.contains("text/html; charset=UTF-8") ?? false)) {
      File file = File(downloadPath);
      String data = file.readAsStringSync();
      file.delete().ignore();

      EHImageException? exception = EHImageExceptionMatcher.match(data);
      log.error('Save ${readPageState.readPageInfo.galleryTitle} image: $index failed, invalid reason: $exception');

      if (exception != null) {
        if (exception.operation == EHImageExceptionAfterOperation.pause) {
          toast(exception.message, isShort: false);
          return;
        } else if (exception.operation == EHImageExceptionAfterOperation.pauseAll) {
          toast(exception.message, isShort: false);
          return;
        } else if (exception.operation == EHImageExceptionAfterOperation.reParse) {
          GalleryImage image;
          try {
            image = await readPageLogic.requestImage(index, true, null);
          } catch (e) {
            log.error('Save original image failed: $e');
            toast('saveFailed'.tr);
            return;
          }

          readPageState.images[index]!.originalImageUrl = image.originalImageUrl;

          return saveOriginalOnlineImage(index);
        }
      } else {
        toast('saveFailed'.tr, isShort: false);
        return;
      }
    }

    try {
      if (GetPlatform.isDesktop) {
        await file.copy(join(downloadSetting.singleImageSavePath.value, fileName));
        toast('saveSuccess'.tr);
      } else {
        bool success = await _saveFile2Album(downloadPath, fileName);
        toast(success ? 'saveSuccess'.tr : 'saveFailed'.tr);
      }
    } catch (e) {
      log.error('Save original online image failed: $e');
      toast('saveFailed'.tr);
    } finally {
      file.delete().ignore();
    }
  }

  /// Save a downloaded-mode image file to the gallery/album or designated save path.
  void saveDownloadedImageFile(int index) {
    String filePath = _getDownloadedImageAbsolutePath(index);
    File image = File(filePath);

    String fileName = basename(image.path);
    if (readPageState.readPageInfo.gid != null && readPageState.readPageInfo.token != null) {
      fileName = '${readPageState.readPageInfo.gid!}_${readPageState.readPageInfo.token!}_$index${extension(image.path)}';
    }

    if (GetPlatform.isDesktop) {
      image.copy(join(downloadSetting.singleImageSavePath.value, fileName)).then((_) => toast('success'.tr));
    } else {
      _saveFile2Album(filePath, fileName).then((_) => toast('success'.tr));
    }
  }

  /// Save an archive-mode image file to the gallery/album or designated save path.
  void saveArchiveImageFile(int index) {
    String filePath = _getArchiveImageAbsolutePath(index);
    File image = File(filePath);

    String fileName = basename(image.path);
    if (readPageState.readPageInfo.gid != null && readPageState.readPageInfo.token != null) {
      fileName = '${readPageState.readPageInfo.gid!}_${readPageState.readPageInfo.token!}_$index${extension(image.path)}';
    }

    if (GetPlatform.isDesktop) {
      image.copy(join(downloadSetting.singleImageSavePath.value, fileName)).then((_) => toast('success'.tr));
    } else {
      _saveFile2Album(filePath, fileName).then((_) => toast('success'.tr));
    }
  }

  void copyEHPageUrl(int index) {
    String? pageUrl;

    if (readPageState.thumbnails[index] != null) {
      pageUrl = readPageState.thumbnails[index]!.replacedMPVHref(index + 1);
    }

    if (pageUrl == null && readPageState.images[index]?.imageHash != null && readPageState.readPageInfo.gid != null) {
      bool isEX = readPageState.readPageInfo.galleryUrl?.contains(EHConsts.EXIndex) == true;
      pageUrl = (isEX ? EHConsts.EXIndex : EHConsts.EHIndex) + '/s/${readPageState.images[index]!.imageHash}/${readPageState.readPageInfo.gid}-${index + 1}';
    }

    if (pageUrl == null) {
      toast('failed'.tr);
      return;
    }

    FlutterClipboard.copy(pageUrl).then((_) => toast('hasCopiedToClipboard'.tr));
  }

  /// Compute image container size when we haven't parsed image's size
  Size getPlaceHolderSize(int imageIndex) {
    if (readPageState.imageContainerSizes[imageIndex] != null) {
      return readPageState.imageContainerSizes[imageIndex]!;
    }
    return Size(double.infinity, readPageState.displayRegionSize.height / 2);
  }

  /// Compute image container size
  FittedSizes getImageFittedSize(Size imageSize) {
    return applyBoxFit(
      BoxFit.contain,
      Size(imageSize.width, imageSize.height),
      Size(readPageState.displayRegionSize.width, double.infinity),
    );
  }

  Alignment _computeAlignmentByTapOffset(Offset offset) {
    return Alignment((offset.dx - Get.size.width / 2) / (Get.size.width / 2), (offset.dy - Get.size.height / 2) / (Get.size.height / 2));
  }

  Future<bool> _ensureSave2AlbumPermission() async {
    List<PermissionStatus> status = await checkAndRequestPermissions();

    if (status.every((e) => e.isGranted)) {
      return true;
    }

    log.warning('Save image to album failed: permission denied, status: $status');

    _showPermissionPermanentlyDeniedDialog();

    return false;
  }

  Future<void> _showPermissionPermanentlyDeniedDialog() async {
    bool? result = await Get.dialog<bool>(
      AlertDialog(
        title: Text('permissionPermanentlyDenied'.tr),
        content: Text('permissionPermanentlyDeniedHint'.tr),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
          TextButton(onPressed: () => Get.back(result: true), child: Text('goToSetting'.tr)),
        ],
        actionsPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 12),
      ),
    );

    if (result == true) {
      await openAppSettings();
    }
  }

  Future<bool> _saveFile2Album(String filePath, String fileName) async {
    if (!await _ensureSave2AlbumPermission()) {
      return false;
    }

    SaveResult saveResult = await SaverGallery.saveFile(
      filePath: filePath,
      fileName: fileName,
      albumPath: "Acervo H&C",
      skipIfExists: false,
    );

    log.info('Save image to album: $saveResult');

    return saveResult.isSuccess;
  }
}
