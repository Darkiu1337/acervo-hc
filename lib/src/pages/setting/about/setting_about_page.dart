import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/extension/widget_extension.dart';
import 'package:acervo_hc/src/service/release_update_service.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/release_update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SettingAboutPage extends StatefulWidget {
  const SettingAboutPage({Key? key}) : super(key: key);

  @override
  _SettingAboutPageState createState() => _SettingAboutPageState();
}

class _SettingAboutPageState extends State<SettingAboutPage> {
  String appName = '';
  String packageName = '';
  String version = '';
  String buildNumber = '';
  String author = 'Darkiu1337';
  String gitRepo = 'https://github.com/Darkiu1337/acervo-hc';
  String helpPage = 'https://github.com/Darkiu1337/acervo-hc#readme';

  bool _checkingUpdate = false;
  String? _updateStatusText;

  @override
  void initState() {
    PackageInfo.fromPlatform().then((packageInfo) {
      if (!mounted) {
        return;
      }
      setState(() {
        appName = packageInfo.appName;
        packageName = packageInfo.packageName;
        version = packageInfo.version;
        buildNumber = packageInfo.buildNumber;
      });
    });
    super.initState();
  }

  Future<void> _handleCheckUpdate() async {
    if (_checkingUpdate) {
      return;
    }

    setState(() {
      _checkingUpdate = true;
      _updateStatusText = 'checkingUpdates'.tr;
    });

    final ReleaseUpdateCheckResult result = await releaseUpdateService.checkForUpdate(force: true);
    if (!mounted) {
      return;
    }

    setState(() {
      _checkingUpdate = false;
      switch (result.status) {
        case ReleaseUpdateStatus.updateAvailable:
          _updateStatusText = '${'newVersionAvailable'.tr}: ${result.release?.tagName ?? ''}';
          break;
        case ReleaseUpdateStatus.upToDate:
          _updateStatusText = 'alreadyLatestVersion'.tr;
          break;
        case ReleaseUpdateStatus.error:
          _updateStatusText = 'checkUpdateFailed'.tr;
          break;
        case ReleaseUpdateStatus.ignored:
        case ReleaseUpdateStatus.throttled:
          _updateStatusText = null;
          break;
      }
    });

    if (result.status == ReleaseUpdateStatus.updateAvailable && result.release != null) {
      await Get.dialog(
        ReleaseUpdateDialog(
          release: result.release!,
          currentVersion: result.currentVersion,
        ),
      );
    } else if (result.status == ReleaseUpdateStatus.upToDate) {
      toast('alreadyLatestVersion'.tr);
    } else if (result.status == ReleaseUpdateStatus.error) {
      toast('checkUpdateFailed'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Acervo H&C')),
      body: ListView(
        padding: const EdgeInsets.only(top: 16),
        children: [
          ListTile(title: Text('version'.tr), subtitle: Text(version.isEmpty ? '1.0.0' : version + (buildNumber.isEmpty ? '' : '+$buildNumber'))),
          ListTile(
            title: Text('checkForUpdates'.tr),
            subtitle: Text(_updateStatusText ?? 'checkForUpdatesHint'.tr),
            trailing: _checkingUpdate
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.system_update_alt),
            onTap: _handleCheckUpdate,
          ),
          ListTile(title: Text('author'.tr), subtitle: SelectableText(author)),
          ListTile(
            title: const Text('Github'),
            subtitle: SelectableText(gitRepo),
            onTap: () => launchUrlString(gitRepo, mode: LaunchMode.externalApplication),
          ),
          ListTile(
            title: Text('Q&A'.tr),
            subtitle: SelectableText(helpPage),
            onTap: () => launchUrlString(helpPage, mode: LaunchMode.externalApplication),
          ),
        ],
      ).withListTileTheme(context),
    );
  }
}
