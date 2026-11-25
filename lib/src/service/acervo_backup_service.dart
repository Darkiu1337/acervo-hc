import 'dart:convert';

import 'package:acervo_hc/src/enum/config_enum.dart';
import 'package:acervo_hc/src/enum/config_type_enum.dart';
import 'package:acervo_hc/src/model/config.dart';
import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/service/already_read_service.dart';
import 'package:acervo_hc/src/service/cloud_service.dart';
import 'package:acervo_hc/src/service/local_config_service.dart';
import 'package:acervo_hc/src/service/local_favorite_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/watched_progress_service.dart';
import 'package:acervo_hc/src/setting/advanced_setting.dart';
import 'package:acervo_hc/src/setting/eh_setting.dart';
import 'package:acervo_hc/src/setting/keyboard_shortcut_setting.dart';
import 'package:acervo_hc/src/setting/mouse_setting.dart';
import 'package:acervo_hc/src/setting/network_setting.dart';
import 'package:acervo_hc/src/setting/performance_setting.dart';
import 'package:acervo_hc/src/setting/preference_setting.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';
import 'package:acervo_hc/src/setting/style_setting.dart';
import 'package:acervo_hc/src/utils/atomic_json_store.dart';

/// Sections that can be exported/imported in a full Acervo H&C local backup.
enum AcervoBackupSection {
  alreadyRead('alreadyRead', 'alreadyRead'),
  localFavorites('localFavorites', 'localFavorites'),
  watchedProgress('watchedProgress', 'watchedProgress'),
  readIndexRecord('readIndexRecord', 'readIndexRecord'),
  quickSearch('quickSearch', 'quickSearchConfig'),
  blockRules('blockRules', 'blockRules'),
  searchHistory('searchHistory', 'searchHistory'),
  history('history', 'galleryHistory'),
  appSettings('appSettings', 'backupAppSettings'),
  ;

  final String key;
  final String labelKey;

  const AcervoBackupSection(this.key, this.labelKey);

  static AcervoBackupSection? tryFromKey(String key) {
    for (final AcervoBackupSection section in values) {
      if (section.key == key) {
        return section;
      }
    }
    return null;
  }

  CloudConfigTypeEnum? get legacyCloudType {
    switch (this) {
      case AcervoBackupSection.readIndexRecord:
        return CloudConfigTypeEnum.readIndexRecord;
      case AcervoBackupSection.quickSearch:
        return CloudConfigTypeEnum.quickSearch;
      case AcervoBackupSection.blockRules:
        return CloudConfigTypeEnum.blockRules;
      case AcervoBackupSection.searchHistory:
        return CloudConfigTypeEnum.searchHistory;
      case AcervoBackupSection.history:
        return CloudConfigTypeEnum.history;
      case AcervoBackupSection.alreadyRead:
      case AcervoBackupSection.localFavorites:
      case AcervoBackupSection.watchedProgress:
      case AcervoBackupSection.appSettings:
        return null;
    }
  }

  static AcervoBackupSection fromLegacyCloudType(CloudConfigTypeEnum type) {
    switch (type) {
      case CloudConfigTypeEnum.readIndexRecord:
        return AcervoBackupSection.readIndexRecord;
      case CloudConfigTypeEnum.quickSearch:
        return AcervoBackupSection.quickSearch;
      case CloudConfigTypeEnum.blockRules:
        return AcervoBackupSection.blockRules;
      case CloudConfigTypeEnum.searchHistory:
        return AcervoBackupSection.searchHistory;
      case CloudConfigTypeEnum.history:
        return AcervoBackupSection.history;
    }
  }
}

enum AcervoBackupImportMode {
  merge,
  replace,
}

/// Parsed representation of either a full `acervo_hc_backup` file or a legacy
/// `JHenTaiConfig` JSON array.
class AcervoBackupDocument {
  static const String formatId = 'acervo_hc_backup';
  static const int currentSchemaVersion = 1;

  final bool isLegacyFormat;
  final int schemaVersion;
  final String? appVersion;
  final DateTime? exportedAt;
  final Map<AcervoBackupSection, dynamic> sections;
  final Map<AcervoBackupSection, int> sectionCounts;

  const AcervoBackupDocument({
    required this.isLegacyFormat,
    required this.schemaVersion,
    required this.appVersion,
    required this.exportedAt,
    required this.sections,
    required this.sectionCounts,
  });

  Set<AcervoBackupSection> get availableSections => sections.keys.toSet();

  /// Parses an already decoded JSON structure (either `Map` for v1 full backup
  /// or `List` for legacy JHenTaiConfig exports).
  factory AcervoBackupDocument.fromDecoded(dynamic decoded) {
    if (decoded is List) {
      final Map<AcervoBackupSection, dynamic> sections = <AcervoBackupSection, dynamic>{};
      final Map<AcervoBackupSection, int> counts = <AcervoBackupSection, int>{};

      for (final dynamic item in decoded) {
        if (item is! Map) {
          continue;
        }
        final CloudConfig config = CloudConfig.fromJson(Map<String, dynamic>.from(item));
        final AcervoBackupSection section = AcervoBackupSection.fromLegacyCloudType(config.type);
        sections[section] = config.toJson();
        counts[section] = _estimateLegacyConfigCount(config);
      }

      if (sections.isEmpty) {
        throw const FormatException('Backup file contains no recognized config entries');
      }

      return AcervoBackupDocument(
        isLegacyFormat: true,
        schemaVersion: 0,
        appVersion: null,
        exportedAt: null,
        sections: sections,
        sectionCounts: counts,
      );
    }

    if (decoded is Map && decoded['format'] == formatId) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      final dynamic rawSections = map['sections'];
      if (rawSections is! Map) {
        throw const FormatException('Invalid Acervo H&C backup: missing sections object');
      }

      final Map<AcervoBackupSection, dynamic> sections = <AcervoBackupSection, dynamic>{};
      final Map<AcervoBackupSection, int> counts = <AcervoBackupSection, int>{};

      rawSections.forEach((dynamic k, dynamic v) {
        final AcervoBackupSection? section = AcervoBackupSection.tryFromKey(k.toString());
        if (section == null || v == null) {
          return;
        }
        sections[section] = v;
        counts[section] = _estimateSectionCount(section, v);
      });

      if (sections.isEmpty) {
        throw const FormatException('Backup file contains no recognized sections');
      }

      DateTime? exportedAt;
      if (map['exportedAt'] is String) {
        exportedAt = DateTime.tryParse(map['exportedAt'] as String);
      }

      return AcervoBackupDocument(
        isLegacyFormat: false,
        schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
        appVersion: map['appVersion']?.toString(),
        exportedAt: exportedAt,
        sections: sections,
        sectionCounts: counts,
      );
    }

    throw const FormatException('Unrecognized backup file format');
  }

  static int _estimateLegacyConfigCount(CloudConfig config) {
    try {
      final dynamic parsed = jsonDecode(config.config);
      if (parsed is List) {
        return parsed.length;
      }
      if (parsed is Map) {
        return parsed.length;
      }
    } catch (_) {}
    return 1;
  }

  static int _estimateSectionCount(AcervoBackupSection section, dynamic value) {
    switch (section) {
      case AcervoBackupSection.alreadyRead:
        return value is List ? value.length : 0;
      case AcervoBackupSection.localFavorites:
        if (value is Map && value['favorites'] is List) {
          return (value['favorites'] as List).length;
        }
        return value is List ? value.length : 0;
      case AcervoBackupSection.watchedProgress:
        if (value is String) {
          try {
            final dynamic parsed = jsonDecode(value);
            if (parsed is Map) {
              final int seen = (parsed['seenGids'] as List?)?.length ?? 0;
              final int bm = (parsed['bookmarks'] as List?)?.length ?? 0;
              return seen + bm;
            }
          } catch (_) {}
        }
        return 1;
      case AcervoBackupSection.appSettings:
        return value is Map ? value.length : 0;
      case AcervoBackupSection.readIndexRecord:
      case AcervoBackupSection.quickSearch:
      case AcervoBackupSection.blockRules:
      case AcervoBackupSection.searchHistory:
      case AcervoBackupSection.history:
        if (value is Map) {
          try {
            return _estimateLegacyConfigCount(CloudConfig.fromJson(Map<String, dynamic>.from(value)));
          } catch (_) {}
        }
        return 1;
    }
  }
}

/// Summary returned after applying an import operation.
class AcervoBackupImportResult {
  final List<AcervoBackupSection> importedSections;
  final Map<AcervoBackupSection, int> importedCounts;

  const AcervoBackupImportResult({
    required this.importedSections,
    required this.importedCounts,
  });
}

AcervoBackupService acervoBackupService = AcervoBackupService();

/// Exports and imports complete Acervo H&C local backups (including fork-specific
/// data such as Already Read with cover hashes, Local Favorites with collections,
/// Watched progress, and safe non-secret app settings), while staying backward
/// compatible with legacy `JHenTaiConfig` files.
class AcervoBackupService {
  /// Safe setting keys exported under [AcervoBackupSection.appSettings].
  /// Intentionally excludes cookies, user credentials, and security PINs.
  static const List<ConfigEnum> safeAppSettingKeys = <ConfigEnum>[
    ConfigEnum.readSetting,
    ConfigEnum.preferenceSetting,
    ConfigEnum.styleSetting,
    ConfigEnum.mouseSetting,
    ConfigEnum.performanceSetting,
    ConfigEnum.keyboardShortcutSetting,
    ConfigEnum.EHSetting,
    ConfigEnum.networkSetting,
    ConfigEnum.advancedSetting,
  ];

  /// Builds a versioned JSON-serializable backup payload for [sections].
  Future<Map<String, dynamic>> buildBackupMap({
    required Set<AcervoBackupSection> sections,
    String? appVersion,
    AlreadyReadService? alreadyRead,
    LocalFavoriteService? localFavorites,
    WatchedProgressService? watchedProgress,
    bool includeLegacyCloudSections = true,
  }) async {
    final AlreadyReadService readSvc = alreadyRead ?? alreadyReadService;
    final LocalFavoriteService favSvc = localFavorites ?? localFavoriteService;
    final WatchedProgressService watchSvc = watchedProgress ?? watchedProgressService;

    final Map<String, dynamic> sectionPayloads = <String, dynamic>{};

    for (final AcervoBackupSection section in sections) {
      switch (section) {
        case AcervoBackupSection.alreadyRead:
          final List<Map<String, dynamic>> entries = readSvc.exportEntries();
          if (entries.isNotEmpty) {
            sectionPayloads[section.key] = entries;
          }
          break;
        case AcervoBackupSection.localFavorites:
          final Map<String, dynamic> payload = favSvc.exportPayload();
          final List<dynamic> favs = payload['favorites'] as List<dynamic>? ?? const <dynamic>[];
          final List<dynamic> cols = payload['collections'] as List<dynamic>? ?? const <dynamic>[];
          if (favs.isNotEmpty || cols.isNotEmpty) {
            sectionPayloads[section.key] = payload;
          }
          break;
        case AcervoBackupSection.watchedProgress:
          if (includeLegacyCloudSections) {
            await watchSvc.ensureLoaded();
          }
          if (watchSvc.seenCount > 0 || watchSvc.bookmarks.isNotEmpty || watchSvc.lastAnchor != null) {
            sectionPayloads[section.key] = watchSvc.toJsonString();
          }
          break;
        case AcervoBackupSection.appSettings:
          if (includeLegacyCloudSections) {
            final Map<String, String> settingsMap = <String, String>{};
            for (final ConfigEnum key in safeAppSettingKeys) {
              final String? raw = await localConfigService.read(configKey: key);
              if (raw != null && raw.isNotEmpty) {
                settingsMap[key.key] = raw;
              }
            }
            if (settingsMap.isNotEmpty) {
              sectionPayloads[section.key] = settingsMap;
            }
          }
          break;
        case AcervoBackupSection.readIndexRecord:
        case AcervoBackupSection.quickSearch:
        case AcervoBackupSection.blockRules:
        case AcervoBackupSection.searchHistory:
        case AcervoBackupSection.history:
          if (includeLegacyCloudSections) {
            final CloudConfig? cfg = await cloudConfigService.getLocalConfig(section.legacyCloudType!);
            if (cfg != null) {
              sectionPayloads[section.key] = cfg.toJson();
            }
          }
          break;
      }
    }

    return <String, dynamic>{
      'format': AcervoBackupDocument.formatId,
      'schemaVersion': AcervoBackupDocument.currentSchemaVersion,
      if (appVersion != null) 'appVersion': appVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'sections': sectionPayloads,
    };
  }

  /// Encodes a backup map off the UI thread.
  Future<String> encodeBackup(Map<String, dynamic> backupMap) {
    return AtomicJsonStore.encodeJsonString(backupMap);
  }

  /// Parses and validates a backup JSON string (v1 full backup or legacy array).
  Future<AcervoBackupDocument> inspectBackup(String rawJson) async {
    final dynamic decoded = await AtomicJsonStore.decodeJsonString(rawJson);
    return AcervoBackupDocument.fromDecoded(decoded);
  }

  /// Applies selected [sections] from [doc] using [mode] (`merge` or `replace`).
  Future<AcervoBackupImportResult> importBackup(
    AcervoBackupDocument doc, {
    required Set<AcervoBackupSection> sections,
    required AcervoBackupImportMode mode,
    AlreadyReadService? alreadyRead,
    LocalFavoriteService? localFavorites,
    WatchedProgressService? watchedProgress,
    bool persistWatched = true,
  }) async {
    final AlreadyReadService readSvc = alreadyRead ?? alreadyReadService;
    final LocalFavoriteService favSvc = localFavorites ?? localFavoriteService;
    final WatchedProgressService watchSvc = watchedProgress ?? watchedProgressService;
    final bool merge = mode == AcervoBackupImportMode.merge;

    final List<AcervoBackupSection> imported = <AcervoBackupSection>[];
    final Map<AcervoBackupSection, int> counts = <AcervoBackupSection, int>{};

    for (final AcervoBackupSection section in sections) {
      if (!doc.sections.containsKey(section)) {
        continue;
      }
      final dynamic value = doc.sections[section];

      switch (section) {
        case AcervoBackupSection.alreadyRead:
          if (value is List) {
            final List<GalleryHistoryModel> entries = <GalleryHistoryModel>[];
            for (final dynamic item in value) {
              if (item is Map) {
                try {
                  entries.add(GalleryHistoryModel.fromJson(Map<String, dynamic>.from(item)));
                } catch (e) {
                  log.warning('Skip invalid alreadyRead entry during import: $e');
                }
              }
            }
            final int count = await readSvc.importEntries(entries, merge: merge);
            imported.add(section);
            counts[section] = count;
          }
          break;

        case AcervoBackupSection.localFavorites:
          final int count = await favSvc.importPayload(value, merge: merge);
          imported.add(section);
          counts[section] = count;
          break;

        case AcervoBackupSection.watchedProgress:
          if (value is String && value.isNotEmpty) {
            await watchSvc.importFromJsonString(value, merge: merge, persist: persistWatched);
            imported.add(section);
            counts[section] = doc.sectionCounts[section] ?? 1;
          }
          break;

        case AcervoBackupSection.appSettings:
          if (value is Map) {
            int applied = 0;
            for (final ConfigEnum key in safeAppSettingKeys) {
              final dynamic raw = value[key.key];
              if (raw is String && raw.isNotEmpty) {
                await localConfigService.write(configKey: key, value: raw);
                applied++;
              }
            }
            if (applied > 0) {
              await _refreshAppSettingsBeans();
              imported.add(section);
              counts[section] = applied;
            }
          }
          break;

        case AcervoBackupSection.readIndexRecord:
        case AcervoBackupSection.quickSearch:
        case AcervoBackupSection.blockRules:
        case AcervoBackupSection.searchHistory:
        case AcervoBackupSection.history:
          if (value is Map) {
            final CloudConfig cfg = CloudConfig.fromJson(Map<String, dynamic>.from(value));
            await cloudConfigService.importConfig(cfg);
            imported.add(section);
            counts[section] = doc.sectionCounts[section] ?? 1;
          }
          break;
      }
    }

    return AcervoBackupImportResult(
      importedSections: imported,
      importedCounts: counts,
    );
  }

  Future<void> _refreshAppSettingsBeans() async {
    await Future.wait(<Future<void>>[
      readSetting.refreshBean(),
      preferenceSetting.refreshBean(),
      styleSetting.refreshBean(),
      mouseSetting.refreshBean(),
      performanceSetting.refreshBean(),
      keyboardShortcutSetting.refreshBean(),
      ehSetting.refreshBean(),
      networkSetting.refreshBean(),
      advancedSetting.refreshBean(),
    ]);
  }
}
