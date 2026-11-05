import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/extension/widget_extension.dart';
import 'package:acervo_hc/src/pages/setting/keyboard_shortcuts/setting_keyboard_shortcuts_page.dart';
import 'package:acervo_hc/src/pages/setting/read/tap_zone/setting_tap_zone_page.dart';
import 'package:acervo_hc/src/pages/setting/upscale/setting_upscale_page.dart';
import 'package:acervo_hc/src/setting/preference_setting.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';
import 'package:acervo_hc/src/setting/style_setting.dart';
import 'package:path/path.dart' as p;

import '../../../routes/routes.dart';
import '../../../service/external_viewer_service.dart';
import '../../../utils/route_util.dart';
import '../../../utils/text_input_formatter.dart';
import '../../../utils/toast_util.dart';
import '../../../widget/eh_alert_dialog.dart';
import '../../../widget/image_viewer_select_dialog.dart';
import '../../home_page.dart';

class SettingReadPage extends StatelessWidget {
  final TextEditingController imageRegionWidthRatioController = TextEditingController(text: readSetting.imageRegionWidthRatio.value.toString());
  final TextEditingController portraitImageRegionWidthRatioController = TextEditingController(text: readSetting.portraitImageRegionWidthRatio.value.toString());
  final TextEditingController landscapeImageRegionWidthRatioController =
  TextEditingController(text: readSetting.landscapeImageRegionWidthRatio.value.toString());
  final TextEditingController imageMaxKilobytesController = TextEditingController(text: readSetting.maxImageKilobyte.value.toString());
  final TextEditingController externalViewerArgsController = TextEditingController(text: readSetting.externalViewerArgs.value ?? '');

  SettingReadPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text('readSetting'.tr)),
      body: Obx(
            () =>
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.only(top: 16),
                children: [
                  if (GetPlatform.isMobile || GetPlatform.isWindows) _buildEnableImmersiveMode().center(),
                  _buildKeepScreenAwake().center(),
                  if (GetPlatform.isMobile) _buildEnableCustomReadBrightness().center(),
                  if (GetPlatform.isMobile) _buildCustomReadBrightness().center(),
                  _buildShowThumbnails().center(),
                  _buildShowScrollBar().center(),
                  _buildShowStatusInfo().center(),
                  if (GetPlatform.isMobile) _buildEnablePageTurnByVolumeKeys().center(),
                  _buildEnablePageTurnAnime().center(),
                  _buildEnableDoubleTapToScaleUp().center(),
                  _buildEnableTapDragToScaleUp().center(),
                  _buildAlignToTopWhenTurnPage().center(),
                  _buildZoomStepPercent().center(),
                  _buildEnableBottomMenu().center(),
                  _buildTapZoneStyle(context).center(),
                  if (GetPlatform.isWindows || GetPlatform.isLinux) _buildUpscaleSettings(context).center(),
                  _buildEnableImageMaxKilobytes().center(),
                  if (readSetting.enableMaxImageKilobyte.isTrue) _buildImageMaxKilobytes(context).fadeIn(const Key('imageMaxKilobytes')).center(),
                  if (GetPlatform.isDesktop) _buildUseThirdPartyViewer().center(),
                  if (GetPlatform.isDesktop) _buildThirdPartyViewerPath(context).center(),
                  if (GetPlatform.isDesktop && (readSetting.thirdPartyViewerPath.value?.trim().isNotEmpty ?? false)) ...[
                    _buildExternalViewerStreamMode().center(),
                    _buildExternalViewerArgs(context).center(),
                    const _ExternalViewerCleanupTile().center(),
                  ],
                  if (GetPlatform.isDesktop) _buildKeyboardShortcuts(context).center(),
                  if (GetPlatform.isMobile) _buildDeviceDirection().center(),
                  if (GetPlatform.isMobile) _buildEnableOrientationSpecificReadDirection().center(),
                  if (GetPlatform.isMobile && readSetting.enableOrientationSpecificReadDirection.isTrue)
                    _buildPortraitReadDirection().fadeIn(const Key('portraitReadDirection')).center(),
                  if (GetPlatform.isMobile && readSetting.enableOrientationSpecificReadDirection.isTrue)
                    _buildLandscapeReadDirection().fadeIn(const Key('landscapeReadDirection')).center(),
                  if (!GetPlatform.isMobile || readSetting.enableOrientationSpecificReadDirection.isFalse) _buildReadDirection().center(),
                  _buildAutoDetectWebtoon().center(),
                  if (GetPlatform.isMobile && readSetting.enableOrientationSpecificReadDirection.isTrue
                      ? (readSetting.portraitReadDirection.value == ReadDirection.top2bottomList ||
                      readSetting.landscapeReadDirection.value == ReadDirection.top2bottomList)
                      : readSetting.readDirection.value == ReadDirection.top2bottomList)
                    _buildNotchOptimization().center(),
                  if (GetPlatform.isMobile && readSetting.enableOrientationSpecificReadDirection.isTrue) ...[
                    if (readSetting.portraitReadDirection.value == ReadDirection.top2bottomList)
                      _buildPortraitImageRegionWidthRatio(context).fadeIn(const Key('portraitImageRegionWidthRatio')).center(),
                    if (readSetting.landscapeReadDirection.value == ReadDirection.top2bottomList)
                      _buildLandscapeImageRegionWidthRatio(context).fadeIn(const Key('landscapeImageRegionWidthRatio')).center(),
                  ],
                  if (!GetPlatform.isMobile || readSetting.enableOrientationSpecificReadDirection.isFalse)
                    if (readSetting.readDirection.value == ReadDirection.top2bottomList) _buildImageRegionWidthRatio(context).center(),
                  if (readSetting.isInListReadDirection) _buildPreloadDistanceInOnlineMode(context).fadeIn(const Key('preloadDistanceInOnlineMode')).center(),
                  if (readSetting.isInListReadDirection) _buildPreloadDistanceInLocalMode(context).fadeIn(const Key('preloadDistanceInLocalMode')).center(),
                  if (!readSetting.isEveryInListReadDirection) _buildPreloadPageCount().fadeIn(const Key('preloadPageCount')).center(),
                  if (!readSetting.isEveryInListReadDirection) _buildPreloadPageCountInLocalMode().fadeIn(const Key('preloadPageCountInLocalMode')).center(),
                  if (GetPlatform.isMobile && readSetting.enableOrientationSpecificReadDirection.isTrue) ...[
                    if (readSetting.portraitReadDirection.value == ReadDirection.left2rightDoubleColumn ||
                        readSetting.portraitReadDirection.value == ReadDirection.right2leftDoubleColumn)
                      _buildPortraitDisplayFirstPageAlone().fadeIn(const Key('portraitDisplayFirstPageAlone')).center(),
                    if (readSetting.landscapeReadDirection.value == ReadDirection.left2rightDoubleColumn ||
                        readSetting.landscapeReadDirection.value == ReadDirection.right2leftDoubleColumn)
                      _buildLandscapeDisplayFirstPageAlone().fadeIn(const Key('landscapeDisplayFirstPageAlone')).center(),
                  ],
                  if (!GetPlatform.isMobile || readSetting.enableOrientationSpecificReadDirection.isFalse)
                    if (readSetting.isInDoubleColumnReadDirection) _buildDisplayFirstPageAlone().fadeIn(const Key('displayFirstPageAloneGlobally')).center(),
                  if (readSetting.isInListReadDirection) _buildAutoModeStyle().fadeIn(const Key('autoModeStyle')).center(),
                  if (readSetting.isInListReadDirection) _buildTurnPageMode().fadeIn(const Key('turnPageMode')).center(),
                  _buildImageSpace().center(),
                ],
              ).withListTileTheme(context),
            ),
      ),
    );
  }

  Widget _buildEnableImmersiveMode() {
    return SwitchListTile(
      title: Text('enableImmersiveMode'.tr),
      subtitle: GetPlatform.isMobile ? Text('enableImmersiveHint'.tr) : Text('enableImmersiveHint4Windows'.tr),
      value: readSetting.enableImmersiveMode.value,
      onChanged: readSetting.saveEnableImmersiveMode,
    );
  }

  Widget _buildKeepScreenAwake() {
    return SwitchListTile(
      title: Text('keepScreenAwakeWhenReading'.tr),
      value: readSetting.keepScreenAwakeWhenReading.value,
      onChanged: readSetting.saveKeepScreenAwakeWhenReading,
    );
  }

  Widget _buildEnableCustomReadBrightness() {
    return SwitchListTile(
      title: Text('enableCustomReadBrightness'.tr),
      value: readSetting.enableCustomReadBrightness.value,
      onChanged: readSetting.saveEnableCustomReadBrightness,
    );
  }

  Widget _buildShowThumbnails() {
    return SwitchListTile(
      title: Text('showThumbnails'.tr),
      value: readSetting.showThumbnails.value,
      onChanged: readSetting.saveShowThumbnails,
    );
  }

  Widget _buildShowScrollBar() {
    return SwitchListTile(
      title: Text('showScrollBar'.tr),
      value: readSetting.showScrollBar.value,
      onChanged: readSetting.saveShowScrollBar,
    );
  }

  Widget _buildCustomReadBrightness() {
    return Row(
      children: [
        const SizedBox(width: 16),
        const Icon(Icons.brightness_6),
        const SizedBox(width: 16),
        Text(readSetting.customBrightness.value.toString()),
        Expanded(
          child: Slider(
            value: readSetting.customBrightness.value.toDouble(),
            onChanged: (double value) => readSetting.saveCustomBrightness(value.toInt()),
            min: 0,
            max: 100,
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildImageSpace() {
    return ListTile(
      title: Text('spaceBetweenImages'.tr),
      trailing: DropdownButton<int>(
        value: readSetting.imageSpace.value,
        elevation: 4,
        onChanged: (int? newValue) {
          readSetting.saveImageSpace(newValue!);
        },
        items: const [
          DropdownMenuItem(
            child: Text('0'),
            value: 0,
          ),
          DropdownMenuItem(
            child: Text('2'),
            value: 2,
          ),
          DropdownMenuItem(
            child: Text('4'),
            value: 4,
          ),
          DropdownMenuItem(
            child: Text('6'),
            value: 6,
          ),
          DropdownMenuItem(
            child: Text('8'),
            value: 7,
          ),
          DropdownMenuItem(
            child: Text('10'),
            value: 10,
          ),
        ],
      ),
    ).marginOnly(right: 12);
  }

  Widget _buildShowStatusInfo() {
    return SwitchListTile(
      title: Text('showStatusInfo'.tr),
      value: readSetting.showStatusInfo.value,
      onChanged: readSetting.saveShowStatusInfo,
    );
  }

  Widget _buildEnablePageTurnByVolumeKeys() {
    return SwitchListTile(
      title: Text('enablePageTurnByVolumeKeys'.tr),
      subtitle: GetPlatform.isIOS ? Text('enablePageTurnByVolumeKeysHint'.tr) : null,
      value: readSetting.enablePageTurnByVolumeKeys.value,
      onChanged: readSetting.saveEnablePageTurnByVolumeKeys,
    );
  }

  Widget _buildEnablePageTurnAnime() {
    return SwitchListTile(
      title: Text('enablePageTurnAnime'.tr),
      value: readSetting.enablePageTurnAnime.value,
      onChanged: readSetting.saveEnablePageTurnAnime,
    );
  }

  Widget _buildEnableDoubleTapToScaleUp() {
    return SwitchListTile(
      title: Text('enableDoubleTapToScaleUp'.tr),
      value: readSetting.enableDoubleTapToScaleUp.value,
      onChanged: readSetting.saveEnableDoubleTapToScaleUp,
    );
  }

  Widget _buildEnableTapDragToScaleUp() {
    return SwitchListTile(
      title: Text('enableTapDragToScaleUp'.tr),
      value: readSetting.enableTapDragToScaleUp.value,
      onChanged: readSetting.saveEnableTapDragToScaleUp,
    );
  }

  Widget _buildAlignToTopWhenTurnPage() {
    return SwitchListTile(
      title: Text('alignToTopWhenTurnPage'.tr),
      subtitle: Text('alignToTopWhenTurnPageHint'.tr),
      value: readSetting.alignToTopWhenTurnPage.value,
      onChanged: readSetting.saveAlignToTopWhenTurnPage,
    );
  }

  Widget _buildZoomStepPercent() {
    return ListTile(
      title: Text('zoomStepPercent'.tr),
      subtitle: Text('zoomStepPercentHint'.tr),
      trailing: DropdownButton<int>(
        value: readSetting.zoomStepPercent.value,
        elevation: 4,
        onChanged: (int? newValue) {
          readSetting.saveZoomStepPercent(newValue!);
        },
        items: const [
          DropdownMenuItem(child: Text('5%'), value: 5),
          DropdownMenuItem(child: Text('8%'), value: 8),
          DropdownMenuItem(child: Text('12%'), value: 12),
          DropdownMenuItem(child: Text('20%'), value: 20),
        ],
      ).marginOnly(right: 12),
    );
  }

  Widget _buildEnableBottomMenu() {
    return SwitchListTile(
      title: Text('enableBottomMenu'.tr),
      value: readSetting.enableBottomMenu.value,
      onChanged: readSetting.saveEnableBottomMenu,
    );
  }

  Widget _buildTapZoneStyle(BuildContext context) {
    return ListTile(
      title: Text('tapZoneStyle'.tr),
      subtitle: Text('tapZoneStyleHint'.tr),
      trailing: const Icon(Icons.keyboard_arrow_right),
      onTap: () {
        final rootNav = Navigator.of(context, rootNavigator: true);
        final nearestNav = Navigator.of(context);
        if (rootNav != nearestNav &&
            nearestNav.widget.key != Get.keys[left] &&
            nearestNav.widget.key != Get.keys[right] &&
            nearestNav.widget.key != Get.keys[leftV2] &&
            nearestNav.widget.key != Get.keys[rightV2]) {
          nearestNav.push(
            PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const SettingTapZonePage(),
                transitionsBuilder: preferenceSetting.enableSwipeBackGesture.isTrue && styleSetting.isInMobileLayout
                    ? (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeInOut,
                      )),
                      child: child,
                    )
                    : (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                transitionDuration: UIConfig.defaultPageRouteTransitionDuration),
          );
        } else {
          toRoute(Routes.settingTapZoneStyle);
        }
      },
    );
  }

  Widget _buildUpscaleSettings(BuildContext context) {
    return ListTile(
      title: Text('upscale'.tr),
      subtitle: Text('upscaleSettingsHint'.tr),
      trailing: const Icon(Icons.keyboard_arrow_right),
      onTap: () {
        final rootNav = Navigator.of(context, rootNavigator: true);
        final nearestNav = Navigator.of(context);
        if (rootNav != nearestNav &&
            nearestNav.widget.key != Get.keys[left] &&
            nearestNav.widget.key != Get.keys[right] &&
            nearestNav.widget.key != Get.keys[leftV2] &&
            nearestNav.widget.key != Get.keys[rightV2]) {
          nearestNav.push(
            PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const SettingUpscalePage(),
                transitionsBuilder: preferenceSetting.enableSwipeBackGesture.isTrue && styleSetting.isInMobileLayout
                    ? (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeInOut,
                      )),
                      child: child,
                    )
                    : (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                transitionDuration: UIConfig.defaultPageRouteTransitionDuration),
          );
        } else {
          toRoute(Routes.settingUpscale);
        }
      },
    );
  }

  Widget _buildEnableImageMaxKilobytes() {
    return SwitchListTile(
      title: Text('enableImageMaxKilobytes'.tr),
      value: readSetting.enableMaxImageKilobyte.value,
      onChanged: readSetting.saveEnableMaxImageKilobyte,
    );
  }

  Widget _buildImageMaxKilobytes(BuildContext context) {
    return ListTile(
      title: Text('imageMaxKilobytes'.tr),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 50,
            child: TextField(
              controller: imageMaxKilobytesController,
              decoration: const InputDecoration(isDense: true, labelStyle: TextStyle(fontSize: 12)),
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, IntRangeTextInputFormatter(minValue: 1)],
            ),
          ),
          Text('KB', style: UIConfig.settingPageListTileTrailingTextStyle(context)),
          IconButton(
            onPressed: () {
              int? value = int.tryParse(imageMaxKilobytesController.value.text);
              if (value == null) {
                return;
              }
              readSetting.saveMaxImageKilobyte(value);
              toast('saveSuccess'.tr);
            },
            icon: Icon(Icons.check, color: UIConfig.resumePauseButtonColor(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceDirection() {
    return ListTile(
      title: Text('deviceOrientation'.tr),
      trailing: DropdownButton<DeviceDirection>(
        value: readSetting.deviceDirection.value,
        elevation: 4,
        onChanged: (DeviceDirection? newValue) => readSetting.saveDeviceDirection(newValue!),
        items: [
          DropdownMenuItem(child: Text('followSystem'.tr), value: DeviceDirection.followSystem),
          DropdownMenuItem(child: Text('landscape'.tr), value: DeviceDirection.landscape),
          DropdownMenuItem(child: Text('portrait'.tr), value: DeviceDirection.portrait),
        ],
      ).marginOnly(right: 12),
    );
  }

  Widget _buildEnableOrientationSpecificReadDirection() {
    return SwitchListTile(
      title: Text('enableOrientationSpecificReadDirection'.tr),
      subtitle: Text('enableOrientationSpecificReadDirectionHint'.tr),
      value: readSetting.enableOrientationSpecificReadDirection.value,
      onChanged: readSetting.saveEnableOrientationSpecificReadDirection,
    );
  }

  Widget _buildPortraitReadDirection() {
    return ListTile(
      title: Text('portraitReadDirection'.tr),
      trailing: DropdownButton<ReadDirection>(
        value: readSetting.portraitReadDirection.value,
        elevation: 4,
        onChanged: (ReadDirection? newValue) => readSetting.savePortraitReadDirection(newValue!),
        items: ReadDirection.values.map((e) => DropdownMenuItem(child: Text(e.name.tr), value: e)).toList(),
      ).marginOnly(right: 12),
    );
  }

  Widget _buildLandscapeReadDirection() {
    return ListTile(
      title: Text('landscapeReadDirection'.tr),
      trailing: DropdownButton<ReadDirection>(
        value: readSetting.landscapeReadDirection.value,
        elevation: 4,
        onChanged: (ReadDirection? newValue) => readSetting.saveLandscapeReadDirection(newValue!),
        items: ReadDirection.values.map((e) => DropdownMenuItem(child: Text(e.name.tr), value: e)).toList(),
      ).marginOnly(right: 12),
    );
  }

  Widget _buildAutoDetectWebtoon() {
    return SwitchListTile(
      title: Text('autoDetectWebtoon'.tr),
      subtitle: Text('autoDetectWebtoonHint'.tr),
      value: readSetting.autoDetectWebtoon.value,
      onChanged: readSetting.saveAutoDetectWebtoon,
    );
  }

  Widget _buildReadDirection() {
    return ListTile(
      title: Text('readDirection'.tr),
      trailing: DropdownButton<ReadDirection>(
        value: readSetting.readDirection.value,
        elevation: 4,
        onChanged: (ReadDirection? newValue) => readSetting.saveReadDirection(newValue!),
        items: ReadDirection.values.map((e) => DropdownMenuItem(child: Text(e.name.tr), value: e)).toList(),
      ).marginOnly(right: 12),
    );
  }

  Widget _buildNotchOptimization() {
    return ListTile(
      title: Text('notchOptimization'.tr),
      subtitle: Text('notchOptimizationHint'.tr),
      trailing: Switch(value: readSetting.notchOptimization.value, onChanged: readSetting.saveNotchOptimization),
    );
  }

  Widget _buildImageRegionWidthRatio(BuildContext context) {
    return ListTile(
      title: Text('imageRegionWidthRatio'.tr),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 50,
            child: TextField(
              controller: imageRegionWidthRatioController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, labelStyle: TextStyle(fontSize: 12)),
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                IntRangeTextInputFormatter(minValue: 1, maxValue: 100),
              ],
              onSubmitted: (_) {
                _saveImageRegionWidthRatio();
              },
            ),
          ),
          const Text('%'),
          IconButton(
            onPressed: _saveImageRegionWidthRatio,
            icon: Icon(Icons.check, color: UIConfig.resumePauseButtonColor(context)),
          ),
        ],
      ),
    ).marginOnly(right: 12);
  }

  void _saveImageRegionWidthRatio() {
    int? value = int.tryParse(imageRegionWidthRatioController.value.text);
    if (value == null) {
      return;
    }
    readSetting.saveImageRegionWidthRatio(value);
    toast('saveSuccess'.tr);
  }

  Widget _buildPortraitImageRegionWidthRatio(BuildContext context) {
    return ListTile(
      title: Text('portraitImageRegionWidthRatio'.tr),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 50,
            child: TextField(
              controller: portraitImageRegionWidthRatioController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, labelStyle: TextStyle(fontSize: 12)),
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                IntRangeTextInputFormatter(minValue: 1, maxValue: 100),
              ],
              onSubmitted: (_) => _savePortraitImageRegionWidthRatio(),
            ),
          ),
          const Text('%'),
          IconButton(
            onPressed: _savePortraitImageRegionWidthRatio,
            icon: Icon(Icons.check, color: UIConfig.resumePauseButtonColor(context)),
          ),
        ],
      ),
    ).marginOnly(right: 12);
  }

  void _savePortraitImageRegionWidthRatio() {
    int? value = int.tryParse(portraitImageRegionWidthRatioController.value.text);
    if (value == null) {
      return;
    }
    readSetting.savePortraitImageRegionWidthRatio(value);
    toast('saveSuccess'.tr);
  }

  Widget _buildLandscapeImageRegionWidthRatio(BuildContext context) {
    return ListTile(
      title: Text('landscapeImageRegionWidthRatio'.tr),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 50,
            child: TextField(
              controller: landscapeImageRegionWidthRatioController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, labelStyle: TextStyle(fontSize: 12)),
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                IntRangeTextInputFormatter(minValue: 1, maxValue: 100),
              ],
              onSubmitted: (_) => _saveLandscapeImageRegionWidthRatio(),
            ),
          ),
          const Text('%'),
          IconButton(
            onPressed: _saveLandscapeImageRegionWidthRatio,
            icon: Icon(Icons.check, color: UIConfig.resumePauseButtonColor(context)),
          ),
        ],
      ),
    ).marginOnly(right: 12);
  }

  void _saveLandscapeImageRegionWidthRatio() {
    int? value = int.tryParse(landscapeImageRegionWidthRatioController.value.text);
    if (value == null) {
      return;
    }
    readSetting.saveLandscapeImageRegionWidthRatio(value);
    toast('saveSuccess'.tr);
  }

  Widget _buildUseThirdPartyViewer() {
    return SwitchListTile(
      title: Text('useThirdPartyViewer'.tr),
      value: readSetting.useThirdPartyViewer.value,
      onChanged: readSetting.saveUseThirdPartyViewer,
    );
  }

  Widget _buildThirdPartyViewerPath(BuildContext context) {
    final String? configuredPath = readSetting.thirdPartyViewerPath.value;
    final String? configuredName = readSetting.thirdPartyViewerName.value;
    final String display = configuredName != null && configuredName.trim().isNotEmpty
        ? configuredName
        : (configuredPath == null || configuredPath.trim().isEmpty ? '' : p.basenameWithoutExtension(configuredPath));

    return ListTile(
      title: Text('thirdPartyViewerPath'.tr),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (display.isNotEmpty) Text(display, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('thirdPartyViewerPathHint'.tr, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      trailing: const Icon(Icons.keyboard_arrow_right),
      onTap: () async {
        final ImageViewerSelection? selection = await Get.dialog<ImageViewerSelection>(
          ImageViewerSelectDialog(currentPath: readSetting.thirdPartyViewerPath.value),
        );
        if (selection == null) {
          return;
        }

        if (selection.isEmpty) {
          await readSetting.saveThirdPartyViewer(path: null, name: null);
        } else {
          await readSetting.saveThirdPartyViewer(path: selection.path, name: selection.name);
        }
      },
    );
  }

  Widget _buildExternalViewerStreamMode() {
    return ListTile(
      title: Text('externalViewerStreamMode'.tr),
      subtitle: Text('externalViewerStreamModeHint'.tr),
      trailing: SizedBox(
        width: 190,
        child: DropdownButton<ExternalViewerStreamMode>(
          value: readSetting.externalViewerStreamMode.value,
          isExpanded: true,
          elevation: 4,
          alignment: AlignmentDirectional.centerEnd,
          onChanged: (ExternalViewerStreamMode? newValue) {
            if (newValue != null) {
              readSetting.saveExternalViewerStreamMode(newValue);
            }
          },
          items: [
            DropdownMenuItem(child: Text('externalViewerStreamModeAuto'.tr), value: ExternalViewerStreamMode.auto),
            DropdownMenuItem(child: Text('externalViewerStreamModeStream'.tr), value: ExternalViewerStreamMode.stream),
            DropdownMenuItem(child: Text('externalViewerStreamModeWaitAll'.tr), value: ExternalViewerStreamMode.waitAll),
          ],
        ),
      ),
    );
  }

  Widget _buildExternalViewerArgs(BuildContext context) {
    return ListTile(
      title: Text('externalViewerArgs'.tr),
      subtitle: Text('externalViewerArgsHint'.tr),
      trailing: SizedBox(
        width: 230,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: TextField(
                controller: externalViewerArgsController,
                decoration: const InputDecoration(isDense: true, labelStyle: TextStyle(fontSize: 12)),
                textAlign: TextAlign.center,
                onSubmitted: (_) => _saveExternalViewerArgs(),
              ),
            ),
            IconButton(
              onPressed: _saveExternalViewerArgs,
              icon: Icon(Icons.check, color: UIConfig.resumePauseButtonColor(context)),
            ),
          ],
        ),
      ),
    );
  }

  void _saveExternalViewerArgs() {
    final String value = externalViewerArgsController.text.trim();
    readSetting.saveExternalViewerArgs(value.isEmpty ? null : value);
    toast('saveSuccess'.tr);
  }

  Widget _buildKeyboardShortcuts(BuildContext context) {
    return ListTile(
      title: Text('keyboardShortcuts'.tr),
      subtitle: Text('keyboardShortcutsHint'.tr),
      trailing: const Icon(Icons.keyboard_arrow_right),
      onTap: () {
        final rootNav = Navigator.of(context, rootNavigator: true);
        final nearestNav = Navigator.of(context);
        if (rootNav != nearestNav &&
            nearestNav.widget.key != Get.keys[left] &&
            nearestNav.widget.key != Get.keys[right] &&
            nearestNav.widget.key != Get.keys[leftV2] &&
            nearestNav.widget.key != Get.keys[rightV2]) {
          nearestNav.push(
            PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const SettingKeyboardShortcutsPage(),
                transitionsBuilder: preferenceSetting.enableSwipeBackGesture.isTrue && styleSetting.isInMobileLayout
                    ? (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeInOut,
                      )),
                      child: child,
                    )
                    : (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                transitionDuration: UIConfig.defaultPageRouteTransitionDuration),
          );
        } else {
          toRoute(Routes.settingKeyboardShortcuts);
        }
      },
    );
  }

  Widget _buildPreloadDistanceInOnlineMode(BuildContext context) {
    return ListTile(
      title: Text('preloadDistanceInOnlineMode'.tr),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<int>(
            value: readSetting.preloadDistance.value,
            elevation: 4,
            onChanged: (int? newValue) {
              readSetting.savePreloadDistance(newValue!);
            },
            items: const [
              DropdownMenuItem(child: Text('0'), value: 0),
              DropdownMenuItem(child: Text('1'), value: 1),
              DropdownMenuItem(child: Text('2'), value: 2),
              DropdownMenuItem(child: Text('3'), value: 3),
              DropdownMenuItem(child: Text('5'), value: 5),
              DropdownMenuItem(child: Text('8'), value: 8),
              DropdownMenuItem(child: Text('10'), value: 10),
            ],
          ),
          Text('ScreenHeight'.tr, style: UIConfig.settingPageListTileTrailingTextStyle(context)).marginSymmetric(horizontal: 12),
        ],
      ),
    );
  }

  Widget _buildPreloadDistanceInLocalMode(BuildContext context) {
    return ListTile(
      title: Text('preloadDistanceInLocalMode'.tr),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<int>(
            value: readSetting.preloadDistanceLocal.value,
            elevation: 4,
            onChanged: (int? newValue) {
              readSetting.savePreloadDistanceLocal(newValue!);
            },
            items: const [
              DropdownMenuItem(child: Text('0'), value: 0),
              DropdownMenuItem(child: Text('1'), value: 1),
              DropdownMenuItem(child: Text('2'), value: 2),
              DropdownMenuItem(child: Text('3'), value: 3),
              DropdownMenuItem(child: Text('5'), value: 5),
              DropdownMenuItem(child: Text('8'), value: 8),
              DropdownMenuItem(child: Text('10'), value: 10),
            ],
          ),
          Text('ScreenHeight'.tr, style: UIConfig.settingPageListTileTrailingTextStyle(context)).marginSymmetric(horizontal: 12),
        ],
      ),
    );
  }

  Widget _buildPreloadPageCount() {
    return ListTile(
      title: Text('preloadPageCount'.tr),
      trailing: DropdownButton<int>(
        value: readSetting.preloadPageCount.value,
        elevation: 4,
        onChanged: (int? newValue) {
          readSetting.savePreloadPageCount(newValue!);
        },
        items: const [
          DropdownMenuItem(child: Text('0'), value: 0),
          DropdownMenuItem(child: Text('1'), value: 1),
          DropdownMenuItem(child: Text('2'), value: 2),
          DropdownMenuItem(child: Text('3'), value: 3),
          DropdownMenuItem(child: Text('5'), value: 5),
          DropdownMenuItem(child: Text('8'), value: 8),
          DropdownMenuItem(child: Text('10'), value: 10),
        ],
      ).marginOnly(right: 12),
    );
  }

  Widget _buildPreloadPageCountInLocalMode() {
    return ListTile(
      title: Text('preloadPageCountInLocalMode'.tr),
      trailing: DropdownButton<int>(
        value: readSetting.preloadPageCountLocal.value,
        elevation: 4,
        onChanged: (int? newValue) {
          readSetting.savePreloadPageCountLocal(newValue!);
        },
        items: const [
          DropdownMenuItem(child: Text('0'), value: 0),
          DropdownMenuItem(child: Text('1'), value: 1),
          DropdownMenuItem(child: Text('2'), value: 2),
          DropdownMenuItem(child: Text('3'), value: 3),
          DropdownMenuItem(child: Text('5'), value: 5),
          DropdownMenuItem(child: Text('8'), value: 8),
          DropdownMenuItem(child: Text('10'), value: 10),
        ],
      ).marginOnly(right: 12),
    );
  }

  Widget _buildDisplayFirstPageAlone() {
    return SwitchListTile(
      title: Text('displayFirstPageAloneGlobally'.tr),
      value: readSetting.displayFirstPageAlone.value,
      onChanged: readSetting.saveDisplayFirstPageAlone,
    );
  }

  Widget _buildPortraitDisplayFirstPageAlone() {
    return SwitchListTile(
      title: Text('portraitDisplayFirstPageAlone'.tr),
      value: readSetting.portraitDisplayFirstPageAlone.value,
      onChanged: readSetting.savePortraitDisplayFirstPageAlone,
    );
  }

  Widget _buildLandscapeDisplayFirstPageAlone() {
    return SwitchListTile(
      title: Text('landscapeDisplayFirstPageAlone'.tr),
      value: readSetting.landscapeDisplayFirstPageAlone.value,
      onChanged: readSetting.saveLandscapeDisplayFirstPageAlone,
    );
  }

  Widget _buildAutoModeStyle() {
    return ListTile(
      title: Text('autoModeStyle'.tr),
      trailing: DropdownButton<AutoModeStyle>(
        value: readSetting.autoModeStyle.value,
        elevation: 4,
        alignment: AlignmentDirectional.centerEnd,
        onChanged: (AutoModeStyle? newValue) => readSetting.saveAutoModeStyle(newValue!),
        items: [
          DropdownMenuItem(child: Text('scroll'.tr), value: AutoModeStyle.scroll),
          DropdownMenuItem(child: Text('turnPage'.tr), value: AutoModeStyle.turnPage),
        ],
      ).marginOnly(right: 12),
    );
  }

  Widget _buildTurnPageMode() {
    return ListTile(
      title: Text('turnPageMode'.tr),
      subtitle: Text('turnPageModeHint'.tr),
      trailing: DropdownButton<TurnPageMode>(
        value: readSetting.turnPageMode.value,
        elevation: 4,
        onChanged: (TurnPageMode? newValue) => readSetting.saveTurnPageMode(newValue!),
        items: [
          DropdownMenuItem(child: Text('image'.tr), value: TurnPageMode.image),
          DropdownMenuItem(child: Text('screen'.tr), value: TurnPageMode.screen),
          DropdownMenuItem(child: Text('adaptive'.tr), value: TurnPageMode.adaptive),
        ],
      ).marginOnly(right: 12),
    );
  }
}

class _ExternalViewerCleanupTile extends StatefulWidget {
  const _ExternalViewerCleanupTile();

  @override
  State<_ExternalViewerCleanupTile> createState() => _ExternalViewerCleanupTileState();
}

class _ExternalViewerCleanupTileState extends State<_ExternalViewerCleanupTile> {
  int? _bytes;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final int bytes = await externalViewerService.tempFolderSize();
    if (mounted) {
      setState(() => _bytes = bytes);
    }
  }

  Future<void> _delete() async {
    final bool? confirmed = await Get.dialog<bool>(EHDialog(title: 'externalViewerCleanupConfirm'.tr));
    if (!mounted || confirmed != true) {
      return;
    }

    setState(() => _deleting = true);
    final int freed = await externalViewerService.clearAllTempFolders();
    if (!mounted) {
      return;
    }

    setState(() {
      _deleting = false;
      _bytes = 0;
    });
    toast(freed > 0 ? 'externalViewerCleanupDone'.trArgs([formatFileSize(freed)]) : 'externalViewerCleanupEmpty'.tr);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final int bytes = _bytes ?? 0;
    final bool hasFiles = bytes > 0;

    return ListTile(
      title: Text('externalViewerCleanup'.tr),
      subtitle: Text('${'externalViewerCleanupHint'.tr}: ${_bytes == null ? '...' : formatFileSize(bytes)}'),
      trailing: _deleting
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: hasFiles ? _delete : null,
            ),
      onTap: hasFiles && !_deleting ? _delete : null,
    );
  }
}
