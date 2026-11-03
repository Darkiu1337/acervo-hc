import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/gallery_image.dart';
import 'package:acervo_hc/src/model/read_page_info.dart';
import 'package:acervo_hc/src/network/eh_request.dart';
import 'package:acervo_hc/src/service/jh_service.dart';
import 'package:acervo_hc/src/service/log.dart';
import 'package:acervo_hc/src/service/path_service.dart';
import 'package:acervo_hc/src/setting/read_setting.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:path/path.dart' as p;

typedef ExternalViewerImageResolver = Future<GalleryImage?> Function(int index);

ExternalViewerService externalViewerService = ExternalViewerService.instance;

/// Stage of the gallery preparation shown by the progress overlay.
enum ExternalViewerStage { preparing, downloading, opening }

/// Snapshot of the work being done before (and while) the external viewer is
/// fed with gallery pages.
class ExternalViewerProgress {
  const ExternalViewerProgress({
    required this.stage,
    required this.galleryTitle,
    required this.done,
    required this.total,
    required this.bytes,
    required this.currentPage,
    required this.cancellable,
  });

  final ExternalViewerStage stage;
  final String galleryTitle;
  final int done;
  final int total;
  final int bytes;
  final int currentPage;
  final bool cancellable;

  ExternalViewerProgress copyWith({
    ExternalViewerStage? stage,
    String? galleryTitle,
    int? done,
    int? total,
    int? bytes,
    int? currentPage,
    bool? cancellable,
  }) {
    return ExternalViewerProgress(
      stage: stage ?? this.stage,
      galleryTitle: galleryTitle ?? this.galleryTitle,
      done: done ?? this.done,
      total: total ?? this.total,
      bytes: bytes ?? this.bytes,
      currentPage: currentPage ?? this.currentPage,
      cancellable: cancellable ?? this.cancellable,
    );
  }
}

String formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final double kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  final double mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(1)} MB';
  }
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

/// Feeds a gallery to the image viewer configured in Settings > Read.
///
/// Online galleries are written into a temporary folder page by page (the
/// current page first, then forward and backward) so the viewer can navigate
/// the whole gallery. The default mode streams pages while the viewer is
/// already open for nomacs (which watches the folder) and downloads everything
/// before launching other viewers, because they usually snapshots the folder
/// list when opened.
///
/// Downloaded, archive and local galleries open the current image file
/// directly. The temporary folder is deleted as soon as the viewer process
/// exits; leftover folders from crashes are swept on startup and whenever the
/// feature is used.
class ExternalViewerService with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  ExternalViewerService._();

  static final ExternalViewerService instance = ExternalViewerService._();

  static const String _tempRootName = 'acervo_hc_viewer';
  static const String _legacyTempRootName = 'jhentai_nomacs';

  static const Set<String> _allowedExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.avif'};

  final Map<String, _ExternalViewerSession> _sessions = {};

  /// Progress of the gallery currently being prepared, consumed by the reader
  /// overlay. `null` when nothing is happening.
  final Rxn<ExternalViewerProgress> progress = Rxn<ExternalViewerProgress>();

  String? _progressGalleryKey;
  bool _cleanupRunning = false;
  Timer? _cleanupTimer;

  @override
  List<JHLifeCircleBean> get initDependencies => [pathService, log, readSetting];

  @override
  Future<void> doInitBean() async {
    await cleanupOrphans();

    /// Keeps an eye on folders left behind by a crash or by a viewer that was
    /// closed after JHenTai was restarted without a session to watch it.
    _cleanupTimer ??= Timer.periodic(const Duration(minutes: 10), (_) => unawaited(cleanupOrphans()));
  }

  @override
  Future<void> doAfterBeanReady() async {}

  bool get isConfigured {
    final String? path = readSetting.thirdPartyViewerPath.value;
    return path != null && path.trim().isNotEmpty;
  }

  Future<void> openOnlineGallery({
    required ReadPageInfo readPageInfo,
    required int startIndex,
    required ExternalViewerImageResolver resolveImage,
  }) async {
    final String? viewerPath = _validViewerPath();
    if (viewerPath == null) {
      toast('externalViewerPathNotSet'.tr, isShort: false);
      return;
    }

    final int pageCount = readPageInfo.pageCount;
    if (startIndex < 0 || startIndex >= pageCount) {
      return;
    }

    final String galleryKey = _galleryKey(readPageInfo);
    if (_sessions.containsKey(galleryKey)) {
      toast('externalViewerAlreadyOpen'.tr);
      return;
    }

    await cleanupOrphans();

    final Directory dir = Directory(p.join(
      pathService.tempDir.path,
      _tempRootName,
      '${galleryKey}_${DateTime.now().millisecondsSinceEpoch}',
    ));

    final _ExternalViewerSession session = _ExternalViewerSession(
      galleryKey: galleryKey,
      galleryTitle: readPageInfo.galleryTitle,
      dir: dir,
      pageCount: pageCount,
      startIndex: startIndex,
      resolveImage: resolveImage,
    );

    /// Register the session before creating the folder so the periodic orphan
    /// sweep cannot see an unowned directory during the async gap.
    _sessions[galleryKey] = session;
    _progressGalleryKey = galleryKey;
    _updateProgress(session, ExternalViewerStage.preparing);

    try {
      await dir.create(recursive: true);
    } catch (e) {
      log.error('Create external viewer temp folder failed', e);
      await _finishSession(session, deleteDirectory: true);
      toast('externalViewerPrepareFailed'.tr, isShort: false);
      return;
    }

    File? first;
    try {
      first = await _ensurePage(session, startIndex);
    } catch (e) {
      log.error('Prepare external viewer page failed', e);
      first = null;
    }
    if (first == null) {
      await _finishSession(session, deleteDirectory: true);
      toast('externalViewerPrepareFailed'.tr, isShort: false);
      return;
    }

    final bool stream = _shouldStream(viewerPath);
    if (!stream) {
      try {
        await _downloadRemaining(session);
      } catch (e) {
        log.error('Download pages for the external viewer failed', e);
      }
      if (session.cancelled) {
        await _finishSession(session, deleteDirectory: true);
        return;
      }
      _updateProgress(session, ExternalViewerStage.opening);
    }

    Process process;
    _updateProgress(session, ExternalViewerStage.opening);
    try {
      process = await _launchViewer(viewerPath, first.path);
    } catch (e) {
      log.error('Start external viewer failed', e);
      await _finishSession(session, deleteDirectory: true);
      toast('externalViewerStartFailed'.tr, isShort: false);
      return;
    }

    session.process = process;
    session.launched = true;
    session.isRunning = true;

    unawaited(_watchViewer(session: session, viewerPath: viewerPath));

    if (stream) {
      _updateProgress(session, ExternalViewerStage.downloading);
      unawaited(_downloadRemaining(session));
    } else {
      _clearProgress(session);
    }
  }

  /// Opens a local file (downloaded/archive/local modes) in the viewer.
  Future<void> openLocalFile(String path) async {
    final String? viewerPath = _validViewerPath();
    if (viewerPath == null) {
      toast('externalViewerPathNotSet'.tr, isShort: false);
      return;
    }

    try {
      await _launchViewer(viewerPath, path);
    } catch (e) {
      log.error('Start external viewer failed', e);
      toast('externalViewerStartFailed'.tr, isShort: false);
    }
  }

  /// Stops the background download. If the viewer was not launched yet, the
  /// temporary folder is removed by [openOnlineGallery] when the loop ends.
  void cancelDownload() {
    final String? key = _progressGalleryKey;
    if (key == null) {
      return;
    }
    final _ExternalViewerSession? session = _sessions[key];
    if (session == null || session.cancelling) {
      return;
    }

    session.cancelling = true;
    session.cancelled = true;
    final ExternalViewerProgress? current = progress.value;
    if (current != null) {
      progress.value = current.copyWith(cancellable: false);
    }
    toast('externalViewerDownloadCancelled'.tr);
  }

  /// Total disk used by this feature (current + legacy folders).
  Future<int> tempFolderSize() async {
    int total = 0;
    for (final String rootName in <String>[_tempRootName, _legacyTempRootName]) {
      total += await _directorySize(Directory(p.join(pathService.tempDir.path, rootName)));
    }
    return total;
  }

  /// Deletes every temporary folder that is not being used by an active
  /// session. Returns the number of bytes freed.
  Future<int> clearAllTempFolders() async {
    final String? viewerPath = _configuredViewerPath();
    final bool? viewerRunning = viewerPath == null ? null : await _isViewerProcessRunning(viewerPath);
    final bool? nomacsRunning = await _isNomacsRunning();
    final DateTime cutoff = DateTime.now().subtract(const Duration(hours: 24));

    int freed = 0;
    for (final String rootName in <String>[_tempRootName, _legacyTempRootName]) {
      final Directory root = Directory(p.join(pathService.tempDir.path, rootName));
      if (!await root.exists()) {
        continue;
      }

      final bool? rootViewerRunning = rootName == _legacyTempRootName ? nomacsRunning : viewerRunning;

      await for (final FileSystemEntity entity in root.list()) {
        if (entity is! Directory || _isActiveSessionDirectory(entity.path)) {
          continue;
        }

        /// While a viewer is (or may be) running, only remove folders old
        /// enough that they cannot belong to the current viewing session.
        if (rootViewerRunning != false) {
          final bool old = (await entity.stat()).modified.isBefore(cutoff);
          if (!old) {
            continue;
          }
        }

        freed += await _directorySize(entity);
        await _deleteDirectory(entity);
      }

      try {
        if (await root.exists() && await root.list().isEmpty) {
          await root.delete();
        }
      } catch (_) {}
    }
    return freed;
  }

  /// Removes folders left behind by crashes or by closing JHenTai before the
  /// viewer. When the viewer is not running, nothing can be using those folders
  /// so they are deleted regardless of age. When it is running, only folders
  /// older than a day are removed to avoid deleting the one it is showing.
  Future<void> cleanupOrphans() async {
    if (_cleanupRunning) {
      return;
    }

    bool hasAnyRoot = false;
    for (final String rootName in <String>[_tempRootName, _legacyTempRootName]) {
      if (await Directory(p.join(pathService.tempDir.path, rootName)).exists()) {
        hasAnyRoot = true;
        break;
      }
    }
    if (!hasAnyRoot) {
      return;
    }

    _cleanupRunning = true;

    try {
      final String? viewerPath = _configuredViewerPath();
      final bool? viewerRunning = viewerPath == null ? null : await _isViewerProcessRunning(viewerPath);
      final bool? nomacsRunning = await _isNomacsRunning();
      final DateTime cutoff = DateTime.now().subtract(const Duration(hours: 24));

      for (final String rootName in <String>[_tempRootName, _legacyTempRootName]) {
        final Directory root = Directory(p.join(pathService.tempDir.path, rootName));
        if (!await root.exists()) {
          continue;
        }

        /// The legacy root belongs to the nomacs build; it must be checked
        /// against nomacs even when the configured viewer is a different one.
        final bool? rootViewerRunning = rootName == _legacyTempRootName ? nomacsRunning : viewerRunning;

        await for (final FileSystemEntity entity in root.list()) {
          if (entity is! Directory || _isActiveSessionDirectory(entity.path)) {
            continue;
          }

          try {
            final bool old = (await entity.stat()).modified.isBefore(cutoff);
            final bool shouldDelete = rootViewerRunning == false || old;
            if (shouldDelete) {
              await _deleteDirectory(entity);
            }
          } catch (e) {
            log.warning('Clean external viewer temp folder failed: ${entity.path}', e);
          }
        }

        try {
          if (await root.exists() && await root.list().isEmpty) {
            await root.delete();
          }
        } catch (_) {}
      }
    } finally {
      _cleanupRunning = false;
    }
  }

  bool _shouldStream(String viewerPath) {
    switch (readSetting.externalViewerStreamMode.value) {
      case ExternalViewerStreamMode.auto:
        /// nomacs watches the folder and picks up new pages automatically.
        return p.basenameWithoutExtension(viewerPath).toLowerCase() == 'nomacs';
      case ExternalViewerStreamMode.stream:
        return true;
      case ExternalViewerStreamMode.waitAll:
        return false;
    }
  }

  Future<Process> _launchViewer(String viewerPath, String targetPath) {
    return Process.start(
      viewerPath,
      _buildViewerArguments(viewerPath, targetPath),
      workingDirectory: p.dirname(viewerPath),
      runInShell: false,
    );
  }

  List<String> _buildViewerArguments(String viewerPath, String targetPath) {
    final String template = (readSetting.externalViewerArgs.value ?? '').trim();
    if (template.isEmpty) {
      /// Keep the nomacs behaviour of the original implementation without
      /// hardcoding a flag for every other viewer.
      if (p.basenameWithoutExtension(viewerPath).toLowerCase() == 'nomacs') {
        return <String>['--private', targetPath];
      }
      return <String>[targetPath];
    }

    final List<String> tokens = _splitArguments(template);
    bool replaced = false;
    final List<String> args = tokens.map((String token) {
      if (!token.contains('{path}')) {
        return token;
      }
      replaced = true;
      return token.replaceAll('{path}', targetPath);
    }).toList();

    if (!replaced) {
      args.add(targetPath);
    }
    return args;
  }

  /// Splits a simple command line template, keeping quoted arguments together.
  /// `{path}` is substituted after splitting, so a path with spaces remains a
  /// single argument.
  List<String> _splitArguments(String raw) {
    final List<String> args = <String>[];
    final StringBuffer current = StringBuffer();
    String? quote;

    for (int i = 0; i < raw.length; i++) {
      final String char = raw[i];

      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          current.write(char);
        }
        continue;
      }

      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }

      if (char.trim().isEmpty) {
        if (current.isNotEmpty) {
          args.add(current.toString());
          current.clear();
        }
        continue;
      }

      current.write(char);
    }

    if (current.isNotEmpty) {
      args.add(current.toString());
    }
    return args;
  }

  Future<void> _watchViewer({required _ExternalViewerSession session, required String viewerPath}) async {
    try {
      /// A second launch of a single-instance viewer forwards the file to the
      /// running instance and exits immediately. In that case the viewer
      /// process name is the signal for when the folder can be deleted.
      final int? earlyExit = await Future.any<int?>([
        session.process!.exitCode,
        Future<int?>.delayed(const Duration(seconds: 2), () => null),
      ]);

      if (earlyExit != null) {
        log.debug('External viewer exited early; waiting for the running viewer instance');
        await _waitForViewerToExit(viewerPath);
      } else {
        await session.process!.exitCode;
      }
    } catch (e) {
      log.warning('Watch external viewer process failed', e);
    } finally {
      session.cancelled = true;
      session.isRunning = false;
      await session.done.future;
      await _finishSession(session, deleteDirectory: true);
    }
  }

  Future<void> _waitForViewerToExit(String viewerPath) async {
    int unknownChecks = 0;

    while (true) {
      final bool? running = await _isViewerProcessRunning(viewerPath);
      if (running == false) {
        return;
      }
      if (running == null) {
        unknownChecks++;
        /// Do not keep the folder forever when the process list cannot be read.
        if (unknownChecks > 20) {
          log.warning('Could not check the external viewer process; leaving the temp folder to the sweep');
          return;
        }
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Future<bool?> _isViewerProcessRunning(String viewerPath) async {
    return _isProcessRunningByName(_processImageName(viewerPath));
  }

  Future<bool?> _isNomacsRunning() async {
    return _isProcessRunningByName(Platform.isWindows ? 'nomacs.exe' : 'nomacs');
  }

  Future<bool?> _isProcessRunningByName(String name) async {
    if (name.isEmpty) {
      return null;
    }

    try {
      if (Platform.isWindows) {
        final ProcessResult result = await Process.run('tasklist', ['/FI', 'IMAGENAME eq $name', '/NH']);
        return result.stdout.toString().toLowerCase().contains(name.toLowerCase());
      }

      final ProcessResult result = await Process.run('pgrep', ['-x', name]);
      return result.exitCode == 0;
    } catch (e) {
      log.warning('Check external viewer process failed', e);
      return null;
    }
  }

  String _processImageName(String viewerPath) {
    final String base = p.basename(viewerPath);
    if (Platform.isWindows) {
      return base.toLowerCase();
    }
    return p.basenameWithoutExtension(base).toLowerCase();
  }

  Future<void> _downloadRemaining(_ExternalViewerSession session) async {
    try {
      /// Forward first. This keeps the pages the user is about to read ready.
      for (int i = session.startIndex + 1; i < session.pageCount; i++) {
        if (session.cancelled) {
          return;
        }
        if (await _ensurePage(session, i) == null) {
          log.warning('External viewer stream stopped at page ${i + 1} to keep the folder contiguous');
          toast('externalViewerPageFailed'.tr, isShort: false);
          return;
        }
      }

      /// Then the pages before the starting point.
      for (int i = session.startIndex - 1; i >= 0; i--) {
        if (session.cancelled) {
          return;
        }
        if (await _ensurePage(session, i) == null) {
          log.warning('External viewer stream stopped at page ${i + 1} to keep the folder contiguous');
          toast('externalViewerPageFailed'.tr, isShort: false);
          return;
        }
      }
    } finally {
      if (session.launched) {
        _clearProgress(session);
      }
      if (!session.done.isCompleted) {
        session.done.complete();
      }
    }
  }

  Future<File?> _ensurePage(_ExternalViewerSession session, int index) async {
    final String base = (index + 1).toString().padLeft(5, '0');

    File? existing;
    try {
      existing = _findExisting(session.dir, base);
    } catch (e) {
      log.warning('Scan external viewer temp folder failed', e);
    }
    if (existing != null) {
      return existing;
    }

    GalleryImage? image;
    try {
      image = await session.resolveImage(index);
    } catch (e) {
      log.error('Resolve image URL for the external viewer failed, page ${index + 1}', e);
      return null;
    }
    if (image == null) {
      return null;
    }

    final String ext;
    final String url;
    try {
      ext = _extensionOf(image.url);
      url = _normalizeUrl(image.url);
    } catch (e) {
      log.error('Invalid image URL for the external viewer, page ${index + 1}', e);
      return null;
    }

    final File target = File(p.join(session.dir.path, '$base$ext'));
    final File part = File('${target.path}.part');

    try {
      /// The reader has usually cached the image already. Using that cache
      /// avoids an extra image request (and an extra view against the image
      /// limit). If it is not cached, getNetworkImageData fetches it.
      Uint8List? data;
      try {
        data = await getNetworkImageData(url, useCache: true);
      } catch (e) {
        log.warning('Read cached image for the external viewer failed, falling back to dio', e);
      }

      if (data != null && data.isNotEmpty) {
        await part.writeAsBytes(data, flush: true);
        if (await _looksLikeHtml(part)) {
          clearDiskCachedImage(url);
          await part.delete();
          data = null;
        }
      }

      if (data == null || data.isEmpty) {
        await ehRequest.download(url: url, path: part.path);
        if (!await part.exists() || await part.length() == 0) {
          return null;
        }

        /// e-hentai/exhentai return an HTML page (with HTTP 200) when the
        /// image limit is reached. Do not hand that to the viewer as an image.
        if (await _looksLikeHtml(part)) {
          clearDiskCachedImage(url);
          await part.delete();
          return null;
        }
      }

      await part.rename(target.path);

      session.downloadedCount++;
      session.bytesWritten += await target.length();
      session.currentPage = index + 1;
      _updateProgress(session, ExternalViewerStage.downloading);
      return target;
    } catch (e) {
      log.error('Download page ${index + 1} for the external viewer failed', e);
      try {
        if (await part.exists()) {
          await part.delete();
        }
      } catch (_) {}
      return null;
    }
  }

  File? _findExisting(Directory dir, String base) {
    if (!dir.existsSync()) {
      return null;
    }
    for (final FileSystemEntity entity in dir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final String name = p.basename(entity.path);
      if (name.startsWith('$base.') && !name.endsWith('.part') && entity.lengthSync() > 0) {
        return entity;
      }
    }
    return null;
  }

  Future<bool> _looksLikeHtml(File file) async {
    final RandomAccessFile raf = await file.open();
    try {
      final Uint8List bytes = await raf.read(64);
      if (bytes.isEmpty) {
        return false;
      }
      final String head = String.fromCharCodes(bytes).toLowerCase();
      return head.contains('<html') || head.contains('<!doctype');
    } finally {
      await raf.close();
    }
  }

  String _extensionOf(String url) {
    String ext = p.extension(Uri.parse(url).path).toLowerCase();
    return _allowedExtensions.contains(ext) ? ext : '.jpg';
  }

  /// Matches [EHImage]'s URL rewrite so we hit the same disk cache entry.
  String _normalizeUrl(String url) {
    Uri uri = Uri.parse(url);
    if (uri.host == 's.exhentai.org') {
      return uri.replace(host: 'ehgt.org').toString();
    }
    return url;
  }

  String _galleryKey(ReadPageInfo info) {
    final String raw = info.gid != null ? '${info.gid}_${info.token ?? ''}' : info.galleryTitle;
    final String safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'gallery' : safe;
  }

  void _updateProgress(_ExternalViewerSession session, ExternalViewerStage stage) {
    if (_progressGalleryKey != session.galleryKey) {
      return;
    }
    progress.value = ExternalViewerProgress(
      stage: stage,
      galleryTitle: session.galleryTitle,
      done: session.downloadedCount,
      total: session.pageCount,
      bytes: session.bytesWritten,
      currentPage: session.currentPage,
      cancellable: !session.cancelling && stage != ExternalViewerStage.opening,
    );
  }

  void _clearProgress(_ExternalViewerSession session) {
    if (_progressGalleryKey != session.galleryKey) {
      return;
    }
    _progressGalleryKey = null;
    progress.value = null;
  }

  Future<void> _finishSession(_ExternalViewerSession session, {required bool deleteDirectory}) async {
    if (identical(_sessions[session.galleryKey], session)) {
      _sessions.remove(session.galleryKey);
    }
    _clearProgress(session);
    if (!session.done.isCompleted) {
      session.done.complete();
    }
    if (deleteDirectory) {
      await _deleteDirectory(session.dir);
    }
  }

  Future<void> _deleteDirectory(Directory dir) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        if (!await dir.exists()) {
          return;
        }
        final int bytes = await _directorySize(dir);
        await dir.delete(recursive: true);
        log.info('External viewer temp folder deleted: ${dir.path} (${formatFileSize(bytes)})');
        return;
      } catch (e) {
        if (attempt == 2) {
          log.warning('Delete external viewer temp folder failed: ${dir.path}', e);
        } else {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
  }

  Future<int> _directorySize(Directory dir) async {
    int total = 0;
    try {
      if (!await dir.exists()) {
        return 0;
      }
      await for (final FileSystemEntity entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  String? _configuredViewerPath() {
    final String? path = readSetting.thirdPartyViewerPath.value;
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    return path;
  }

  String? _validViewerPath() {
    final String? path = _configuredViewerPath();
    if (path == null || !File(path).existsSync()) {
      return null;
    }
    return path;
  }

  bool _isActiveSessionDirectory(String path) {
    return _sessions.values.any((session) => p.equals(p.normalize(session.dir.path), p.normalize(path)));
  }
}

class _ExternalViewerSession {
  _ExternalViewerSession({
    required this.galleryKey,
    required this.galleryTitle,
    required this.dir,
    required this.pageCount,
    required this.startIndex,
    required this.resolveImage,
  }) {
    currentPage = startIndex + 1;
  }

  final String galleryKey;
  final String galleryTitle;
  final Directory dir;
  final int pageCount;
  final int startIndex;
  final ExternalViewerImageResolver resolveImage;

  final Completer<void> done = Completer<void>();

  Process? process;
  bool isRunning = false;
  bool launched = false;
  bool cancelled = false;
  bool cancelling = false;
  int downloadedCount = 0;
  int bytesWritten = 0;
  late int currentPage;
}
