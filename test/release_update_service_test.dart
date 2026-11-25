import 'package:acervo_hc/src/service/release_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReleaseVersionComparator', () {
    test('compares semver tags with optional v prefix and build numbers', () {
      expect(ReleaseVersionComparator.isNewer('v1.6.0', '1.5.1'), isTrue);
      expect(ReleaseVersionComparator.isNewer('v1.5.2', '1.5.1+10'), isTrue);
      expect(ReleaseVersionComparator.isNewer('v2.0.0', '1.9.9'), isTrue);
      expect(ReleaseVersionComparator.isNewer('v1.5.1', '1.5.1+10'), isFalse);
      expect(ReleaseVersionComparator.isNewer('v1.5.0', '1.5.1'), isFalse);
    });

    test('treats stable release as newer than pre-release of same version', () {
      expect(ReleaseVersionComparator.isNewer('v1.6.0', '1.6.0-beta.1'), isTrue);
      expect(ReleaseVersionComparator.isNewer('v1.6.0-beta.1', '1.6.0'), isFalse);
      expect(ReleaseVersionComparator.isNewer('v1.6.0-beta.2', '1.6.0-beta.1'), isTrue);
    });
  });

  group('ReleaseUpdateInfo', () {
    final ReleaseUpdateInfo release = ReleaseUpdateInfo.fromGitHubJson(<String, dynamic>{
      'tag_name': 'v1.6.0',
      'name': 'Acervo H&C 1.6.0',
      'body': '- Backup completo\n- Busca unificada',
      'html_url': 'https://github.com/Darkiu1337/acervo-hc/releases/tag/v1.6.0',
      'published_at': '2026-11-25T12:00:00Z',
      'assets': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'AcervoHC_1.6.0+11_Windows_reader.zip',
          'browser_download_url': 'https://example.com/win.zip',
          'size': 25000000,
        },
        <String, dynamic>{
          'name': 'AcervoHC_1.6.0+11_Linux_x64.AppImage',
          'browser_download_url': 'https://example.com/linux.AppImage',
          'size': 28000000,
        },
        <String, dynamic>{
          'name': 'AcervoHC_1.6.0_android.apk',
          'browser_download_url': 'https://example.com/android.apk',
          'size': 22000000,
        },
      ],
    });

    test('selects the right platform asset for Windows, Linux, Android, and null when missing', () {
      expect(release.version, '1.6.0');
      expect(release.selectAssetForPlatform('windows')?.name, 'AcervoHC_1.6.0+11_Windows_reader.zip');
      expect(release.selectAssetForPlatform('linux')?.name, 'AcervoHC_1.6.0+11_Linux_x64.AppImage');
      expect(release.selectAssetForPlatform('android')?.name, 'AcervoHC_1.6.0_android.apk');
      expect(release.selectAssetForPlatform('macos'), isNull);
    });
  });
}
