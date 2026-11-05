import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/l18n/locale_text.dart';
import 'package:acervo_hc/src/network/eh_request.dart';
import 'package:acervo_hc/src/network/jh_request.dart';
import 'package:acervo_hc/src/routes/getx_router_observer.dart';
import 'package:acervo_hc/src/routes/routes.dart';
import 'package:acervo_hc/src/pages/home_page.dart';
import 'package:acervo_hc/src/service/app_update_service.dart';
import 'package:acervo_hc/src/service/archive_download_service.dart';
import 'package:acervo_hc/src/service/built_in_blocked_user_service.dart';
import 'package:acervo_hc/src/service/cloud_service.dart';
import 'package:acervo_hc/src/service/external_viewer_service.dart';
import 'package:acervo_hc/src/service/frame_rate_service.dart';
import 'package:acervo_hc/src/service/gallery_download/gallery_download_service.dart';
import 'package:acervo_hc/src/service/history_service.dart';
import 'package:acervo_hc/src/service/isolate_service.dart';
import 'package:acervo_hc/src/service/jh_service.dart';
import 'package:acervo_hc/src/service/legacy_source_cleanup_service.dart';
import 'package:acervo_hc/src/service/local_block_rule_service.dart';
import 'package:acervo_hc/src/service/local_config_service.dart';
import 'package:acervo_hc/src/service/local_gallery_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/neural_upscale_service.dart';
import 'package:acervo_hc/src/service/path_service.dart';
import 'package:acervo_hc/src/service/quick_search_service.dart';
import 'package:acervo_hc/src/service/read_progress_service.dart';
import 'package:acervo_hc/src/service/schedule_service.dart';
import 'package:acervo_hc/src/service/search_history_service.dart';
import 'package:acervo_hc/src/service/storage_service.dart';
import 'package:acervo_hc/src/service/tag_search_order_service.dart';
import 'package:acervo_hc/src/service/tag_translation_service.dart';
import 'package:acervo_hc/src/service/volume_service.dart';
import 'package:acervo_hc/src/service/windows_service.dart';
import 'package:acervo_hc/src/setting/advanced_setting.dart';
import 'package:acervo_hc/src/setting/archive_bot_setting.dart';
import 'package:acervo_hc/src/setting/download_setting.dart';
import 'package:acervo_hc/src/setting/eh_setting.dart';
import 'package:acervo_hc/src/setting/favorite_setting.dart';
import 'package:acervo_hc/src/setting/keyboard_shortcut_setting.dart';
import 'package:acervo_hc/src/setting/mouse_setting.dart';
import 'package:acervo_hc/src/setting/my_tags_setting.dart';
import 'package:acervo_hc/src/setting/network_setting.dart';
import 'package:acervo_hc/src/setting/performance_setting.dart';
import 'package:acervo_hc/src/setting/preference_setting.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';
import 'package:acervo_hc/src/setting/security_setting.dart';
import 'package:acervo_hc/src/setting/site_setting.dart';
import 'package:acervo_hc/src/setting/style_setting.dart';
import 'package:acervo_hc/src/setting/user_setting.dart';
import 'package:acervo_hc/src/widget/app_manager.dart';

import 'config/theme_config.dart';
import 'network/archive_bot_request.dart';

List<JHLifeCircleBean> lifeCircleBeans = [
  ehRequest,
  jhRequest,
  archiveBotRequest,
  legacySourceCleanupService,
  appUpdateService,
  galleryDownloadService,
  archiveDownloadService,
  localGalleryService,
  cloudConfigService,
  frameRateService,
  historyService,
  isolateService,
  localBlockRuleService,
  localConfigService,
  readProgressService,
  log,
  pathService,
  quickSearchService,
  scheduleService,
  searchHistoryService,
  storageService,
  tagTranslationService,
  tagSearchOrderOptimizationService,
  volumeService,
  windowService,
  advancedSetting,
  downloadSetting,
  archiveBotSetting,
  ehSetting,
  favoriteSetting,
  mouseSetting,
  myTagsSetting,
  networkSetting,
  performanceSetting,
  preferenceSetting,
  readSetting,
  securitySetting,
  siteSetting,
  styleSetting,
  userSetting,
  keyboardShortcutSetting,
  builtInBlockedUserService,
  externalViewerService,
];

void main(List<String> args) async {
  launchArguments = args;

  if (GetPlatform.isDesktop && runWebViewTitleBarWidget(args)) {
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarColor: Colors.transparent,
  ));

  lifeCircleBeans = topologicalSort(lifeCircleBeans);
  for (JHLifeCircleBean bean in lifeCircleBeans) {
    await bean.initBean();
  }

  /// Safety net for a crash or a forced kill: the neural page cache is meant to
  /// live only inside one run of the app.
  unawaited(neuralUpscaleService.clearDiskCache());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget app = GetMaterialApp(
      title: 'Acervo H&C',
      themeMode: styleSetting.themeMode.value,
      theme: ThemeConfig.theme(styleSetting.lightThemeColor.value, Brightness.light),
      darkTheme: ThemeConfig.theme(styleSetting.darkThemeColor.value, Brightness.dark),

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('ko', 'KR'),
        Locale('pt', 'BR'),
      ],
      locale: preferenceSetting.locale.value,
      fallbackLocale: const Locale('en', 'US'),
      translations: LocaleText(),

      getPages: Routes.pages,
      initialRoute: securitySetting.enablePasswordAuth.isTrue || securitySetting.enableBiometricAuth.isTrue ? Routes.lock : Routes.home,
      navigatorObservers: [GetXRouterObserver()],
      builder: (context, child) => AppManager(child: child!),

      /// enable swipe back feature
      popGesture: preferenceSetting.enableSwipeBackGesture.isTrue,
      onReady: () {
        for (JHLifeCircleBean bean in lifeCircleBeans) {
          bean.afterBeanReady();
        }
      },
    );

    /// https://github.com/flutter/flutter/issues/182444
    if (Platform.isWindows) {
      app = ExcludeSemantics(child: app);
    }
    return app;
  }
}

List<JHLifeCircleBean> topologicalSort(List<JHLifeCircleBean> lifeCircleBeans) {
  // Maps to store the visiting state and result order
  final visiting = <JHLifeCircleBean, bool>{};
  final visited = <JHLifeCircleBean, bool>{};
  final result = <JHLifeCircleBean>[];

  // Helper function for DFS
  void visit(JHLifeCircleBean node) {
    if (visited.containsKey(node)) {
      return;
    }
    if (visiting[node] == true) {
      throw Exception('Circular dependency detected');
    }
    visiting[node] = true;
    for (final dependency in node.initDependencies) {
      visit(dependency);
    }
    visiting[node] = false;
    visited[node] = true;
    result.add(node);
  }

  // Visit all nodes
  for (final node in lifeCircleBeans) {
    visit(node);
  }

  return result.toList();
}
