import 'dart:convert';
import 'dart:ui';

import 'package:get/get.dart';
import 'package:acervo_hc/src/enum/config_enum.dart';
import 'package:acervo_hc/src/model/neural_upscale_config.dart';
import 'package:acervo_hc/src/model/tap_zone_config.dart';
import 'package:acervo_hc/src/service/log.dart';

import '../service/jh_service.dart';

ReadSetting readSetting = ReadSetting();

class ReadSetting with JHLifeCircleBeanWithConfigStorage implements JHLifeCircleBean {
  RxBool enableImmersiveMode = true.obs;
  RxBool keepScreenAwakeWhenReading = true.obs;
  RxBool enableCustomReadBrightness = false.obs;
  RxInt customBrightness = 50.obs;
  RxInt imageSpace = 6.obs;
  RxBool showThumbnails = true.obs;
  RxBool showScrollBar = true.obs;
  RxBool showStatusInfo = true.obs;
  RxBool enablePageTurnByVolumeKeys = (GetPlatform.isIOS ? false : true).obs;
  RxBool enablePageTurnAnime = true.obs;
  RxBool enableDoubleTapToScaleUp = false.obs;
  RxBool enableTapDragToScaleUp = false.obs;

  /// Build a 2x bicubic + CAS copy of each page so zoomed images stay crisp.
  RxBool enableUpscale = true.obs;

  /// Run the neural upscaler (Real-CUGAN) on the visible page. Beta, off until
  /// the user downloads the model.
  RxBool enableNeuralUpscale = false.obs;

  /// Model family used by the neural upscaler.
  Rx<NeuralUpscaleModel> neuralUpscaleModel = NeuralUpscaleModel.se.obs;

  /// `-1` disables denoise; `0` is conservative; `1..3` are stronger denoise.
  RxInt neuralUpscaleDenoise = 0.obs;

  /// How many pages ahead of the visible one are pre-enhanced.
  RxInt neuralUpscalePreload = 2.obs;

  /// Align a zoomed page to its top edge when the reader turns the page.
  RxBool alignToTopWhenTurnPage = true.obs;

  /// Zoom step (in percent) applied by ctrl+wheel and by the +/- keys.
  RxInt zoomStepPercent = 8.obs;
  RxBool enableBottomMenu = false.obs;
  Rx<DeviceDirection> deviceDirection = DeviceDirection.followSystem.obs;
  Rx<ReadDirection> readDirection = GetPlatform.isMobile ? ReadDirection.top2bottomList.obs : ReadDirection.left2rightList.obs;
  RxBool enableOrientationSpecificReadDirection = false.obs;
  Rx<ReadDirection> portraitReadDirection = GetPlatform.isMobile ? ReadDirection.top2bottomList.obs : ReadDirection.left2rightList.obs;
  Rx<ReadDirection> landscapeReadDirection = ReadDirection.left2rightList.obs;
  RxBool notchOptimization = false.obs;
  RxInt imageRegionWidthRatio = 100.obs;
  RxInt portraitImageRegionWidthRatio = 100.obs;
  RxInt landscapeImageRegionWidthRatio = 100.obs;
  RxnString tapZoneConfigJson = RxnString();
  RxBool useThirdPartyViewer = false.obs;
  RxnString thirdPartyViewerPath = RxnString();

  /// Friendly name of the selected viewer (shown instead of the full path).
  RxnString thirdPartyViewerName = RxnString();

  /// How pages are handed to the external image viewer.
  Rx<ExternalViewerStreamMode> externalViewerStreamMode = ExternalViewerStreamMode.auto.obs;

  /// Optional argument template for the external viewer. `{path}` is replaced
  /// by the file/folder path; when empty only the path is passed.
  RxnString externalViewerArgs = RxnString();
  RxDouble autoModeInterval = 2.0.obs;
  Rx<AutoModeStyle> autoModeStyle = AutoModeStyle.turnPage.obs;
  Rx<TurnPageMode> turnPageMode = TurnPageMode.adaptive.obs;
  RxInt preloadDistance = 1.obs;
  RxInt preloadDistanceLocal = GetPlatform.isIOS ? 3.obs : 8.obs;
  RxInt preloadPageCount = 1.obs;
  RxInt preloadPageCountLocal = 3.obs;
  RxBool displayFirstPageAlone = true.obs;
  RxBool portraitDisplayFirstPageAlone = true.obs;
  RxBool landscapeDisplayFirstPageAlone = true.obs;
  RxBool enableMaxImageKilobyte =
      (GetPlatform.isDesktop || PlatformDispatcher.instance.views.first.physicalSize.width / PlatformDispatcher.instance.views.first.devicePixelRatio >= 600)
          ? false.obs
          : true.obs;
  RxInt maxImageKilobyte = (1024 * 5).obs;
  RxBool autoDetectWebtoon = false.obs;

  static bool isListDirection(ReadDirection d) =>
      d == ReadDirection.top2bottomList ||
      d == ReadDirection.left2rightList ||
      d == ReadDirection.right2leftList;

  static bool isDoubleColumnDirection(ReadDirection d) =>
      d == ReadDirection.left2rightDoubleColumn || d == ReadDirection.right2leftDoubleColumn;

  static bool isSinglePageDirection(ReadDirection d) =>
      d == ReadDirection.left2rightSinglePage ||
      d == ReadDirection.right2leftSinglePage ||
      d == ReadDirection.left2rightSinglePageFitWidth ||
      d == ReadDirection.right2leftSinglePageFitWidth;

  static bool isFitWidthDirection(ReadDirection d) =>
      d == ReadDirection.left2rightSinglePageFitWidth || d == ReadDirection.right2leftSinglePageFitWidth;

  static bool isRight2LeftDirection(ReadDirection d) =>
      d == ReadDirection.right2leftSinglePage ||
      d == ReadDirection.right2leftSinglePageFitWidth ||
      d == ReadDirection.right2leftDoubleColumn ||
      d == ReadDirection.right2leftList;

  bool get isInListReadDirection {
    if (enableOrientationSpecificReadDirection.isTrue && GetPlatform.isMobile) {
      return isListDirection(portraitReadDirection.value) || isListDirection(landscapeReadDirection.value);
    }
    return isListDirection(readDirection.value);
  }

  bool get isEveryInListReadDirection {
    if (enableOrientationSpecificReadDirection.isTrue && GetPlatform.isMobile) {
      return isListDirection(portraitReadDirection.value) && isListDirection(landscapeReadDirection.value);
    }
    return isListDirection(readDirection.value);
  }

  bool get isInSinglePageReadDirection {
    if (enableOrientationSpecificReadDirection.isTrue && GetPlatform.isMobile) {
      return isSinglePageDirection(portraitReadDirection.value) || isSinglePageDirection(landscapeReadDirection.value);
    }
    return isSinglePageDirection(readDirection.value);
  }

  bool get isInFitWidthReadDirection {
    if (enableOrientationSpecificReadDirection.isTrue && GetPlatform.isMobile) {
      return isFitWidthDirection(portraitReadDirection.value) || isFitWidthDirection(landscapeReadDirection.value);
    }
    return isFitWidthDirection(readDirection.value);
  }

  bool get isInDoubleColumnReadDirection {
    if (enableOrientationSpecificReadDirection.isTrue && GetPlatform.isMobile) {
      return isDoubleColumnDirection(portraitReadDirection.value) || isDoubleColumnDirection(landscapeReadDirection.value);
    }
    return isDoubleColumnDirection(readDirection.value);
  }

  bool get isInRight2LeftDirection {
    if (enableOrientationSpecificReadDirection.isTrue && GetPlatform.isMobile) {
      return isRight2LeftDirection(portraitReadDirection.value) || isRight2LeftDirection(landscapeReadDirection.value);
    }
    return isRight2LeftDirection(readDirection.value);
  }

  @override
  ConfigEnum get configEnum => ConfigEnum.readSetting;

  @override
  void applyBeanConfig(String configString) {
    Map map = jsonDecode(configString);

    enableImmersiveMode.value = map['enableImmersiveMode'];
    keepScreenAwakeWhenReading.value = map['keepScreenAwakeWhenReading'] ?? keepScreenAwakeWhenReading.value;
    enableCustomReadBrightness.value = map['enableCustomReadBrightness'] ?? enableCustomReadBrightness.value;
    customBrightness.value = map['customBrightness'] ?? customBrightness.value;
    imageSpace.value = map['imageSpace'] ?? imageSpace.value;
    showThumbnails.value = map['showThumbnails'] ?? showThumbnails.value;
    showScrollBar.value = map['showScrollBar'] ?? showScrollBar.value;
    showStatusInfo.value = map['showStatusInfo'] ?? showStatusInfo.value;
    enablePageTurnByVolumeKeys.value = map['enablePageTurnByVolumeKeys'] ?? enablePageTurnByVolumeKeys.value;
    enablePageTurnAnime.value = map['enablePageTurnAnime'];
    enableDoubleTapToScaleUp.value = map['enableDoubleTapToScaleUp'] ?? enableDoubleTapToScaleUp.value;
    enableTapDragToScaleUp.value = map['enableTapDragToScaleUp'] ?? enableTapDragToScaleUp.value;
    enableUpscale.value = map['enableUpscale'] ?? enableUpscale.value;
    enableNeuralUpscale.value = map['enableNeuralUpscale'] ?? enableNeuralUpscale.value;
    final int neuralModelIndex = (map['neuralUpscaleModel'] as num?)?.toInt() ?? 0;
    neuralUpscaleModel.value = NeuralUpscaleModel.values[
        neuralModelIndex >= 0 && neuralModelIndex < NeuralUpscaleModel.values.length ? neuralModelIndex : 0];
    neuralUpscaleDenoise.value = ((map['neuralUpscaleDenoise'] as num?)?.toInt() ?? 0).clamp(-1, 3).toInt();
    neuralUpscalePreload.value = ((map['neuralUpscalePreload'] as num?)?.toInt() ?? 2).clamp(0, 3).toInt();
    _normalizeNeuralDenoise();
    alignToTopWhenTurnPage.value = map['alignToTopWhenTurnPage'] ?? alignToTopWhenTurnPage.value;
    zoomStepPercent.value = (map['zoomStepPercent'] as num?)?.toInt() ?? zoomStepPercent.value;
    enableBottomMenu.value = map['enableBottomMenu'] ?? enableBottomMenu.value;
    autoModeInterval.value = (map['autoModeInterval'] as num?)?.toDouble() ?? autoModeInterval.value;
    autoModeStyle.value = AutoModeStyle.values[map['autoModeStyle'] ?? AutoModeStyle.scroll.index];
    deviceDirection.value = DeviceDirection.values[map['deviceDirection'] ?? DeviceDirection.followSystem.index];
    readDirection.value = ReadDirection.values[map['readDirection']];
    notchOptimization.value = map['notchOptimization'] ?? notchOptimization.value;
    imageRegionWidthRatio.value = map['imageRegionWidthRatio'] ?? imageRegionWidthRatio.value;
    portraitImageRegionWidthRatio.value = map['portraitImageRegionWidthRatio'] ?? map['imageRegionWidthRatio'] ?? portraitImageRegionWidthRatio.value;
    landscapeImageRegionWidthRatio.value = map['landscapeImageRegionWidthRatio'] ?? map['imageRegionWidthRatio'] ?? landscapeImageRegionWidthRatio.value;
    tapZoneConfigJson.value = map['tapZoneConfig'] ?? TapZoneConfig.classic().toJsonString();
    _cachedTapZoneConfig = null;
    useThirdPartyViewer.value = map['useThirdPartyViewer'] ?? useThirdPartyViewer.value;
    thirdPartyViewerPath.value = map['thirdPartyViewerPath'];
    thirdPartyViewerName.value = map['thirdPartyViewerName'];
    externalViewerStreamMode.value = ExternalViewerStreamMode.values[map['externalViewerStreamMode'] ?? ExternalViewerStreamMode.auto.index];
    externalViewerArgs.value = map['externalViewerArgs'];
    turnPageMode.value = TurnPageMode.values[map['turnPageMode']];
    preloadDistance.value = map['preloadDistance'];
    preloadDistanceLocal.value = map['preloadDistanceLocal'] ?? preloadDistanceLocal.value;
    preloadPageCount.value = map['preloadPageCount'];
    preloadPageCountLocal.value = map['preloadPageCountLocal'] ?? preloadPageCountLocal.value;
    displayFirstPageAlone.value = map['displayFirstPageAlone'] ?? displayFirstPageAlone.value;
    portraitDisplayFirstPageAlone.value = map['portraitDisplayFirstPageAlone'] ?? map['displayFirstPageAlone'] ?? portraitDisplayFirstPageAlone.value;
    landscapeDisplayFirstPageAlone.value = map['landscapeDisplayFirstPageAlone'] ?? map['displayFirstPageAlone'] ?? landscapeDisplayFirstPageAlone.value;
    enableMaxImageKilobyte.value = map['enableMaxImageKilobyte'] ?? enableMaxImageKilobyte.value;
    maxImageKilobyte.value = map['maxImageKilobyte'] ?? maxImageKilobyte.value;
    enableOrientationSpecificReadDirection.value = map['enableOrientationSpecificReadDirection'] ?? enableOrientationSpecificReadDirection.value;
    autoDetectWebtoon.value = map['autoDetectWebtoon'] ?? autoDetectWebtoon.value;
    /// On first load, migrate existing readDirection to both portrait and landscape
    portraitReadDirection.value = ReadDirection.values[map['portraitReadDirection'] ?? map['readDirection']];
    landscapeReadDirection.value = ReadDirection.values[map['landscapeReadDirection'] ?? map['readDirection']];
  }

  @override
  String toConfigString() {
    return jsonEncode({
      'enableImmersiveMode': enableImmersiveMode.value,
      'keepScreenAwakeWhenReading': keepScreenAwakeWhenReading.value,
      'enableCustomReadBrightness': enableCustomReadBrightness.value,
      'customBrightness': customBrightness.value,
      'imageSpace': imageSpace.value,
      'showThumbnails': showThumbnails.value,
      'showScrollBar': showScrollBar.value,
      'showStatusInfo': showStatusInfo.value,
      'enablePageTurnByVolumeKeys': enablePageTurnByVolumeKeys.value,
      'enablePageTurnAnime': enablePageTurnAnime.value,
      'enableDoubleTapToScaleUp': enableDoubleTapToScaleUp.value,
      'enableTapDragToScaleUp': enableTapDragToScaleUp.value,
      'enableUpscale': enableUpscale.value,
      'enableNeuralUpscale': enableNeuralUpscale.value,
      'neuralUpscaleModel': neuralUpscaleModel.value.index,
      'neuralUpscaleDenoise': neuralUpscaleDenoise.value,
      'neuralUpscalePreload': neuralUpscalePreload.value,
      'alignToTopWhenTurnPage': alignToTopWhenTurnPage.value,
      'zoomStepPercent': zoomStepPercent.value,
      'enableBottomMenu': enableBottomMenu.value,
      'autoModeInterval': autoModeInterval.value,
      'autoModeStyle': autoModeStyle.value.index,
      'deviceDirection': deviceDirection.value.index,
      'readDirection': readDirection.value.index,
      'notchOptimization': notchOptimization.value,
      'imageRegionWidthRatio': imageRegionWidthRatio.value,
      'portraitImageRegionWidthRatio': portraitImageRegionWidthRatio.value,
      'landscapeImageRegionWidthRatio': landscapeImageRegionWidthRatio.value,
      'tapZoneConfig': tapZoneConfigJson.value,
      'useThirdPartyViewer': useThirdPartyViewer.value,
      'thirdPartyViewerPath': thirdPartyViewerPath.value,
      'thirdPartyViewerName': thirdPartyViewerName.value,
      'externalViewerStreamMode': externalViewerStreamMode.value.index,
      'externalViewerArgs': externalViewerArgs.value,
      'turnPageMode': turnPageMode.value.index,
      'preloadDistance': preloadDistance.value,
      'preloadDistanceLocal': preloadDistanceLocal.value,
      'preloadPageCount': preloadPageCount.value,
      'preloadPageCountLocal': preloadPageCountLocal.value,
      'displayFirstPageAlone': displayFirstPageAlone.value,
      'portraitDisplayFirstPageAlone': portraitDisplayFirstPageAlone.value,
      'landscapeDisplayFirstPageAlone': landscapeDisplayFirstPageAlone.value,
      'enableMaxImageKilobyte': enableMaxImageKilobyte.value,
      'maxImageKilobyte': maxImageKilobyte.value,
      'enableOrientationSpecificReadDirection': enableOrientationSpecificReadDirection.value,
      'autoDetectWebtoon': autoDetectWebtoon.value,
      'portraitReadDirection': portraitReadDirection.value.index,
      'landscapeReadDirection': landscapeReadDirection.value.index,
    });
  }

  @override
  Future<void> doInitBean() async {}

  @override
  void doAfterBeanReady() {}

  Future<void> saveEnableImmersiveMode(bool value) async {
    log.debug('saveEnableImmersiveMode:$value');
    enableImmersiveMode.value = value;
    await saveBeanConfig();
  }

  Future<void> saveKeepScreenAwakeWhenReading(bool value) async {
    log.debug('saveKeepScreenAwakeWhenReading:$value');
    keepScreenAwakeWhenReading.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnableCustomReadBrightness(bool value) async {
    log.debug('saveEnableCustomReadBrightness:$value');
    enableCustomReadBrightness.value = value;
    await saveBeanConfig();
  }

  Future<void> saveCustomBrightness(int value) async {
    log.debug('saveCustomBrightness:$value');
    customBrightness.value = value;
    await saveBeanConfig();
  }

  Future<void> saveImageSpace(int value) async {
    log.debug('saveImageSpace:$value');
    imageSpace.value = value;
    await saveBeanConfig();
  }

  Future<void> saveShowThumbnails(bool value) async {
    log.debug('saveShowThumbnails:$value');
    showThumbnails.value = value;
    await saveBeanConfig();
  }

  Future<void> saveShowScrollBar(bool value) async {
    log.debug('saveShowScrollBar:$value');
    showScrollBar.value = value;
    await saveBeanConfig();
  }

  Future<void> saveShowStatusInfo(bool value) async {
    log.debug('saveShowStatusInfo:$value');
    showStatusInfo.value = value;
    await saveBeanConfig();
  }

  Future<void> saveAutoModeInterval(double value) async {
    log.debug('saveAutoModeInterval:$value');
    autoModeInterval.value = value;
    await saveBeanConfig();
  }

  Future<void> saveAutoModeStyle(AutoModeStyle value) async {
    log.debug('saveAutoModeStyle:${value.name}');
    autoModeStyle.value = value;
    await saveBeanConfig();
  }

  Future<void> saveDeviceDirection(DeviceDirection value) async {
    log.debug('saveDeviceDirection:${value.name}');
    deviceDirection.value = value;
    await saveBeanConfig();
  }

  Future<void> saveReadDirection(ReadDirection value) async {
    log.debug('saveReadDirection:${value.name}');
    readDirection.value = value;
    await saveBeanConfig();
  }

  Future<void> saveNotchOptimization(bool value) async {
    log.debug('saveNotchOptimization:$value');
    notchOptimization.value = value;
    await saveBeanConfig();
  }

  Future<void> saveImageRegionWidthRatio(int value) async {
    log.debug('saveImageRegionWidthRatio:$value');
    imageRegionWidthRatio.value = value;
    await saveBeanConfig();
  }

  Future<void> savePortraitImageRegionWidthRatio(int value) async {
    log.debug('savePortraitImageRegionWidthRatio:$value');
    portraitImageRegionWidthRatio.value = value;
    await saveBeanConfig();
  }

  Future<void> saveLandscapeImageRegionWidthRatio(int value) async {
    log.debug('saveLandscapeImageRegionWidthRatio:$value');
    landscapeImageRegionWidthRatio.value = value;
    await saveBeanConfig();
  }

  TapZoneConfig? _cachedTapZoneConfig;

  TapZoneConfig get tapZoneConfig {
    if (_cachedTapZoneConfig != null) {
      return _cachedTapZoneConfig!;
    }
    String? json = tapZoneConfigJson.value;
    if (json == null) {
      return _cachedTapZoneConfig = TapZoneConfig.classic();
    }
    try {
      return _cachedTapZoneConfig = TapZoneConfig.fromJsonString(json);
    } catch (e) {
      log.error('Failed to parse tapZoneConfig, fallback to classic', e);
      return _cachedTapZoneConfig = TapZoneConfig.classic();
    }
  }

  Future<void> saveTapZoneConfig(TapZoneConfig value) async {
    log.debug('saveTapZoneConfig:${value.toJsonString()}');
    _cachedTapZoneConfig = value;
    tapZoneConfigJson.value = value.toJsonString();
    await saveBeanConfig();
  }

  Future<void> saveUseThirdPartyViewer(bool value) async {
    log.debug('saveUseThirdPartyViewer:$value');
    useThirdPartyViewer.value = value;
    await saveBeanConfig();
  }

  Future<void> saveThirdPartyViewerPath(String? value) async {
    log.debug('saveThirdPartyViewerPath:$value');
    thirdPartyViewerPath.value = value;
    await saveBeanConfig();
  }

  /// Saves the selected viewer path and its friendly name together.
  Future<void> saveThirdPartyViewer({String? path, String? name}) async {
    log.debug('saveThirdPartyViewer:$path ($name)');
    thirdPartyViewerPath.value = path;
    thirdPartyViewerName.value = name;
    await saveBeanConfig();
  }

  Future<void> saveExternalViewerStreamMode(ExternalViewerStreamMode value) async {
    log.debug('saveExternalViewerStreamMode:${value.name}');
    externalViewerStreamMode.value = value;
    await saveBeanConfig();
  }

  Future<void> saveExternalViewerArgs(String? value) async {
    log.debug('saveExternalViewerArgs:$value');
    externalViewerArgs.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnablePageTurnByVolumeKeys(bool value) async {
    log.debug('saveEnablePageTurnByVolumeKeys:$value');
    enablePageTurnByVolumeKeys.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnablePageTurnAnime(bool value) async {
    log.debug('saveEnablePageTurnAnime:$value');
    enablePageTurnAnime.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnableDoubleTapToScaleUp(bool value) async {
    log.debug('saveEnableDoubleTapToScaleUp:$value');
    enableDoubleTapToScaleUp.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnableTapDragToScaleUp(bool value) async {
    log.debug('saveEnableTapDragToScaleUp:$value');
    enableTapDragToScaleUp.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnableUpscale(bool value) async {
    log.debug('saveEnableUpscale:$value');
    enableUpscale.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnableNeuralUpscale(bool value) async {
    log.debug('saveEnableNeuralUpscale:$value');
    enableNeuralUpscale.value = value;
    await saveBeanConfig();
  }

  Future<void> saveNeuralUpscaleModel(NeuralUpscaleModel value) async {
    log.debug('saveNeuralUpscaleModel:${value.name}');
    neuralUpscaleModel.value = value;
    _normalizeNeuralDenoise();
    await saveBeanConfig();
  }

  Future<void> saveNeuralUpscaleDenoise(int value) async {
    log.debug('saveNeuralUpscaleDenoise:$value');
    neuralUpscaleDenoise.value = value.clamp(-1, 3).toInt();
    await saveBeanConfig();
  }

  Future<void> saveNeuralUpscalePreload(int value) async {
    log.debug('saveNeuralUpscalePreload:$value');
    neuralUpscalePreload.value = value.clamp(0, 3).toInt();
    await saveBeanConfig();
  }

  /// The Pro package only ships conservative, denoise-3 and no-denoise
  /// weights; 1 and 2 would make the binary look for files that do not exist.
  void _normalizeNeuralDenoise() {
    if (neuralUpscaleModel.value == NeuralUpscaleModel.pro &&
        (neuralUpscaleDenoise.value == 1 || neuralUpscaleDenoise.value == 2)) {
      neuralUpscaleDenoise.value = 0;
    }
  }

  Future<void> saveAlignToTopWhenTurnPage(bool value) async {
    log.debug('saveAlignToTopWhenTurnPage:$value');
    alignToTopWhenTurnPage.value = value;
    await saveBeanConfig();
  }

  Future<void> saveZoomStepPercent(int value) async {
    log.debug('saveZoomStepPercent:$value');
    zoomStepPercent.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnableBottomMenu(bool value) async {
    log.debug('saveEnableBottomMenu:$value');
    enableBottomMenu.value = value;
    await saveBeanConfig();
  }

  Future<void> saveTurnPageMode(TurnPageMode value) async {
    log.debug('saveTurnPageMode:${value.name}');
    turnPageMode.value = value;
    await saveBeanConfig();
  }

  Future<void> savePreloadDistance(int value) async {
    log.debug('savePreloadDistance:$value');
    preloadDistance.value = value;
    await saveBeanConfig();
  }

  Future<void> savePreloadDistanceLocal(int value) async {
    log.debug('savePreloadDistanceLocal:$value');
    preloadDistanceLocal.value = value;
    await saveBeanConfig();
  }

  Future<void> savePreloadPageCount(int value) async {
    log.debug('savePreloadPageCount:$value');
    preloadPageCount.value = value;
    await saveBeanConfig();
  }

  Future<void> savePreloadPageCountLocal(int value) async {
    log.debug('savePreloadPageCountLocal:$value');
    preloadPageCountLocal.value = value;
    await saveBeanConfig();
  }

  Future<void> saveDisplayFirstPageAlone(bool value) async {
    log.debug('saveDisplayFirstPageAlone:$value');
    displayFirstPageAlone.value = value;
    await saveBeanConfig();
  }

  Future<void> savePortraitDisplayFirstPageAlone(bool value) async {
    log.debug('savePortraitDisplayFirstPageAlone:$value');
    portraitDisplayFirstPageAlone.value = value;
    await saveBeanConfig();
  }

  Future<void> saveLandscapeDisplayFirstPageAlone(bool value) async {
    log.debug('saveLandscapeDisplayFirstPageAlone:$value');
    landscapeDisplayFirstPageAlone.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnableMaxImageKilobyte(bool value) async {
    log.debug('saveEnableMaxImageKilobyte:$value');
    enableMaxImageKilobyte.value = value;
    await saveBeanConfig();
  }

  Future<void> saveMaxImageKilobyte(int value) async {
    log.debug('saveMaxImageKilobyte:$value');
    maxImageKilobyte.value = value;
    await saveBeanConfig();
  }

  Future<void> saveEnableOrientationSpecificReadDirection(bool value) async {
    log.debug('saveEnableOrientationSpecificReadDirection:$value');
    enableOrientationSpecificReadDirection.value = value;
    await saveBeanConfig();
  }

  Future<void> saveAutoDetectWebtoon(bool value) async {
    log.debug('saveAutoDetectWebtoon:$value');
    autoDetectWebtoon.value = value;
    await saveBeanConfig();
  }

  Future<void> savePortraitReadDirection(ReadDirection value) async {
    log.debug('savePortraitReadDirection:${value.name}');
    portraitReadDirection.value = value;
    await saveBeanConfig();
  }

  Future<void> saveLandscapeReadDirection(ReadDirection value) async {
    log.debug('saveLandscapeReadDirection:${value.name}');
    landscapeReadDirection.value = value;
    await saveBeanConfig();
  }
}

enum DeviceDirection { followSystem, landscape, portrait }

enum ReadDirection {
  top2bottomList,
  left2rightSinglePage,
  left2rightSinglePageFitWidth,
  left2rightDoubleColumn,
  left2rightList,
  right2leftSinglePage,
  right2leftSinglePageFitWidth,
  right2leftDoubleColumn,
  right2leftList,
}

enum TurnPageMode {
  image,
  screen,

  /// if one image covers the whole screen => screen
  /// else => image
  adaptive,
}

enum AutoModeStyle {
  scroll,
  turnPage,
}

/// How an online gallery is prepared for the external image viewer.
enum ExternalViewerStreamMode {
  /// Stream to viewers known to watch the folder (nomacs); wait for the rest.
  auto,

  /// Write the current page and keep downloading while the viewer is open.
  /// The viewer must watch the folder for new pages to appear.
  stream,

  /// Download every page before launching the viewer. Required by viewers
  /// that only read the folder once when opened.
  waitAll,
}
