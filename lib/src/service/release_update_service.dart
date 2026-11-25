import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:acervo_hc/src/service/jh_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/storage_service.dart';
import 'package:acervo_hc/src/widget/release_update_dialog.dart';

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int sizeBytes;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: (json['name'] ?? '').toString(),
      downloadUrl: (json['browser_download_url'] ?? '').toString(),
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReleaseUpdateInfo {
  final String tagName;
  final String version;
  final String title;
  final String body;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  const ReleaseUpdateInfo({
    required this.tagName,
    required this.version,
    required this.title,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
  });

  factory ReleaseUpdateInfo.fromGitHubJson(Map<String, dynamic> json) {
    final String tag = (json['tag_name'] ?? '').toString().trim();
    final String normalized = ReleaseVersionComparator.normalizeTag(tag);
    final List<ReleaseAsset> assets = (json['assets'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map m) => ReleaseAsset.fromJson(Map<String, dynamic>.from(m)))
        .where((ReleaseAsset a) => a.name.isNotEmpty && a.downloadUrl.isNotEmpty)
        .toList();

    return ReleaseUpdateInfo(
      tagName: tag,
      version: normalized,
      title: (json['name'] ?? tag).toString().trim(),
      body: (json['body'] ?? '').toString().trim(),
      htmlUrl: (json['html_url'] ?? 'https://github.com/Darkiu1337/acervo-hc/releases/latest').toString(),
      publishedAt: json['published_at'] is String ? DateTime.tryParse(json['published_at'] as String) : null,
      assets: assets,
    );
  }

  /// Picks the best downloadable release asset for [operatingSystem]
  /// (`windows`, `linux`, `android`, `macos`, `ios`), or `null` if none match.
  ReleaseAsset? selectAssetForPlatform(String operatingSystem) {
    final String os = operatingSystem.toLowerCase();
    if (assets.isEmpty) {
      return null;
    }

    ReleaseAsset? findFirst(bool Function(String lowerName) predicate) {
      for (final ReleaseAsset asset in assets) {
        if (predicate(asset.name.toLowerCase())) {
          return asset;
        }
      }
      return null;
    }

    switch (os) {
      case 'windows':
        return findFirst((String n) => n.contains('windows') && n.endsWith('.zip')) ??
            findFirst((String n) => n.endsWith('.exe')) ??
            findFirst((String n) => n.endsWith('.zip'));
      case 'linux':
        return findFirst((String n) => n.endsWith('.appimage')) ??
            findFirst((String n) => n.endsWith('.deb')) ??
            findFirst((String n) => n.contains('linux'));
      case 'android':
        return findFirst((String n) => n.endsWith('.apk'));
      case 'macos':
        return findFirst((String n) => n.endsWith('.dmg')) ??
            findFirst((String n) => n.contains('macos'));
      case 'ios':
        return findFirst((String n) => n.endsWith('.ipa'));
      default:
        return null;
    }
  }
}

/// Pure semver comparator for GitHub Release tags vs `pubspec.yaml` versions.
class ReleaseVersionComparator {
  static String normalizeTag(String raw) {
    String cleaned = raw.trim();
    if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
      cleaned = cleaned.substring(1);
    }
    final int plusIdx = cleaned.indexOf('+');
    if (plusIdx >= 0) {
      cleaned = cleaned.substring(0, plusIdx);
    }
    return cleaned.trim();
  }

  /// Returns `true` when [candidate] is strictly newer than [current].
  static bool isNewer(String candidate, String current) {
    return compare(candidate, current) > 0;
  }

  /// Compares two version strings (`>0` if a > b, `0` if equal, `<0` if a < b).
  static int compare(String aRaw, String bRaw) {
    final _ParsedVersion a = _ParsedVersion.parse(aRaw);
    final _ParsedVersion b = _ParsedVersion.parse(bRaw);

    final int maxLen = a.core.length > b.core.length ? a.core.length : b.core.length;
    for (int i = 0; i < maxLen; i++) {
      final int av = i < a.core.length ? a.core[i] : 0;
      final int bv = i < b.core.length ? b.core[i] : 0;
      if (av != bv) {
        return av.compareTo(bv);
      }
    }

    // Stable release beats pre-release of the same core version.
    if (a.preRelease == null && b.preRelease == null) {
      return 0;
    }
    if (a.preRelease == null) {
      return 1;
    }
    if (b.preRelease == null) {
      return -1;
    }
    return a.preRelease!.compareTo(b.preRelease!);
  }
}

class _ParsedVersion {
  final List<int> core;
  final String? preRelease;

  const _ParsedVersion(this.core, this.preRelease);

  factory _ParsedVersion.parse(String raw) {
    final String normalized = ReleaseVersionComparator.normalizeTag(raw);
    final int dashIdx = normalized.indexOf('-');
    final String corePart = dashIdx >= 0 ? normalized.substring(0, dashIdx) : normalized;
    final String? pre = dashIdx >= 0 ? normalized.substring(dashIdx + 1) : null;

    final List<int> nums = corePart
        .split('.')
        .map((String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    return _ParsedVersion(nums, (pre == null || pre.isEmpty) ? null : pre);
  }
}

enum ReleaseUpdateStatus {
  updateAvailable,
  upToDate,
  ignored,
  throttled,
  error,
}

class ReleaseUpdateCheckResult {
  final ReleaseUpdateStatus status;
  final String currentVersion;
  final ReleaseUpdateInfo? release;
  final String? errorMessage;

  const ReleaseUpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.release,
    this.errorMessage,
  });
}

ReleaseUpdateService releaseUpdateService = ReleaseUpdateService();

/// Checks GitHub Releases (`Darkiu1337/acervo-hc`) periodically on startup and
/// on demand from the About page.
class ReleaseUpdateService with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  static const String latestReleaseEndpoint = 'https://api.github.com/repos/Darkiu1337/acervo-hc/releases/latest';
  static const String _lastCheckedKey = 'releaseUpdateLastCheckedMs';
  static const String _ignoredTagKey = 'releaseUpdateIgnoredTag';
  static const Duration _autoCheckInterval = Duration(hours: 24);

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: const <String, dynamic>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'AcervoHC-App',
      },
    ),
  );

  ReleaseUpdateInfo? latestRelease;

  @override
  List<JHLifeCircleBean> get initDependencies => super.initDependencies..add(storageService);

  @override
  Future<void> doInitBean() async {}

  @override
  Future<void> doAfterBeanReady() async {
    unawaited(_autoCheckOnStartup());
  }

  String? get ignoredTag {
    try {
      return storageService.read<String>(_ignoredTagKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> ignoreTag(String tagName) async {
    await storageService.write(_ignoredTagKey, tagName);
  }

  Future<void> clearIgnoredTag() async {
    await storageService.remove(_ignoredTagKey);
  }

  Future<void> _autoCheckOnStartup() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    final ReleaseUpdateCheckResult result = await checkForUpdate(force: false);
    if (result.status == ReleaseUpdateStatus.updateAvailable && result.release != null) {
      if (Get.context != null && !(Get.isDialogOpen ?? false)) {
        await Get.dialog(
          ReleaseUpdateDialog(
            release: result.release!,
            currentVersion: result.currentVersion,
          ),
        );
      }
    }
  }

  /// Queries GitHub Releases for the latest version.
  ///
  /// When [force] is `false`, respects the 24-hour throttle and the user's
  /// ignored release tag.
  Future<ReleaseUpdateCheckResult> checkForUpdate({bool force = false}) async {
    String currentVersion = '0.0.0';
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      currentVersion = info.version;
    } catch (e) {
      log.warning('Failed to read PackageInfo for update check: $e');
    }

    if (!force) {
      final int? lastCheckedMs = storageService.read<int>(_lastCheckedKey);
      if (lastCheckedMs != null) {
        final Duration elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastCheckedMs));
        if (elapsed < _autoCheckInterval) {
          return ReleaseUpdateCheckResult(
            status: ReleaseUpdateStatus.throttled,
            currentVersion: currentVersion,
            release: latestRelease,
          );
        }
      }
    }

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(latestReleaseEndpoint);
      final dynamic data = response.data;
      if (data is! Map) {
        return ReleaseUpdateCheckResult(
          status: ReleaseUpdateStatus.error,
          currentVersion: currentVersion,
          errorMessage: 'Unexpected response format',
        );
      }

      final ReleaseUpdateInfo info = ReleaseUpdateInfo.fromGitHubJson(Map<String, dynamic>.from(data));
      latestRelease = info;
      await storageService.write(_lastCheckedKey, DateTime.now().millisecondsSinceEpoch);

      if (!ReleaseVersionComparator.isNewer(info.version, currentVersion)) {
        return ReleaseUpdateCheckResult(
          status: ReleaseUpdateStatus.upToDate,
          currentVersion: currentVersion,
          release: info,
        );
      }

      if (!force && ignoredTag == info.tagName) {
        return ReleaseUpdateCheckResult(
          status: ReleaseUpdateStatus.ignored,
          currentVersion: currentVersion,
          release: info,
        );
      }

      return ReleaseUpdateCheckResult(
        status: ReleaseUpdateStatus.updateAvailable,
        currentVersion: currentVersion,
        release: info,
      );
    } catch (e) {
      log.debug('GitHub release update check failed: $e');
      return ReleaseUpdateCheckResult(
        status: ReleaseUpdateStatus.error,
        currentVersion: currentVersion,
        errorMessage: e.toString(),
      );
    }
  }

  /// Helper exposing the current platform OS string for asset resolution.
  static String currentPlatformOs() => Platform.operatingSystem;
}
