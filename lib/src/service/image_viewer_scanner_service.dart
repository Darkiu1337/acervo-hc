import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:acervo_hc/src/service/log.dart';

ImageViewerScannerService imageViewerScannerService = const ImageViewerScannerService();

/// One image viewer found on the machine.
class ImageViewerEntry {
  const ImageViewerEntry({
    required this.name,
    required this.path,
    required this.source,
  });

  final String name;
  final String path;

  /// `win32` for regular executables, `store` for packaged (MSIX/Store) apps.
  final String source;

  bool get isStoreApp => source == 'store';
}

/// Lists the image viewers installed for the current Windows user.
///
/// The list comes from the same registry entries used by the "Open with" menu
/// plus packaged applications whose manifest exposes a full-trust executable
/// (for example ImageGlass from the Microsoft Store). True UWP applications
/// without an executable cannot receive a file path on the command line and
/// are intentionally not listed.
class ImageViewerScannerService {
  const ImageViewerScannerService();

  static const String _scriptAsset = 'assets/scripts/scan_image_viewers.ps1';

  Future<List<ImageViewerEntry>> scan() async {
    if (!Platform.isWindows) {
      return const <ImageViewerEntry>[];
    }

    Directory? tempDir;
    try {
      final String script = await rootBundle.loadString(_scriptAsset);

      tempDir = await Directory.systemTemp.createTemp('acervo_hc_viewer_scan_');
      final File scriptFile = File('${tempDir.path}${Platform.pathSeparator}scan_image_viewers.ps1');
      await scriptFile.writeAsString(script, flush: true);

      final ProcessResult result = await Process.run(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptFile.path,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
        runInShell: false,
      ).timeout(const Duration(seconds: 30));

      if (result.exitCode != 0) {
        log.warning('Scan installed image viewers failed (${result.exitCode}): ${result.stderr}');
        return const <ImageViewerEntry>[];
      }

      String stdout = result.stdout.toString();
      if (stdout.isNotEmpty && stdout.codeUnitAt(0) == 0xFEFF) {
        stdout = stdout.substring(1);
      }
      if (stdout.trim().isEmpty) {
        return const <ImageViewerEntry>[];
      }

      final dynamic decoded = jsonDecode(stdout);
      if (decoded is! Map) {
        return const <ImageViewerEntry>[];
      }

      final dynamic rawViewers = decoded['viewers'];
      if (rawViewers == null) {
        return const <ImageViewerEntry>[];
      }
      final List<dynamic> items = rawViewers is List ? rawViewers : <dynamic>[rawViewers];

      final List<ImageViewerEntry> viewers = <ImageViewerEntry>[];
      for (final dynamic item in items) {
        if (item is! Map) {
          continue;
        }
        final String? name = item['name']?.toString();
        final String? path = item['path']?.toString();
        if (path == null || path.trim().isEmpty) {
          continue;
        }
        viewers.add(ImageViewerEntry(
          name: (name == null || name.trim().isEmpty) ? path : name,
          path: path,
          source: item['source']?.toString() ?? 'win32',
        ));
      }

      viewers.sort((ImageViewerEntry a, ImageViewerEntry b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return viewers;
    } on TimeoutException {
      log.warning('Scan installed image viewers timed out');
      return const <ImageViewerEntry>[];
    } catch (e) {
      log.warning('Scan installed image viewers failed', e);
      return const <ImageViewerEntry>[];
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
