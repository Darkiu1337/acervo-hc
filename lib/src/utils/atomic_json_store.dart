import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:acervo_hc/src/service/isolate_service.dart';
import 'package:acervo_hc/src/service/log.dart';

/// Asynchronous, crash-safe JSON file store backed by atomic `temp -> rename`
/// writes and off-UI-thread encoding/decoding via [isolateService].
///
/// Concurrent writes are serialized through an internal queue so rapid
/// mutations never race on the temporary file or overwrite newer snapshots
/// with older ones.
class AtomicJsonStore {
  final Directory Function() directoryProvider;
  final String fileName;

  Future<void> _writeChain = Future<void>.value();

  AtomicJsonStore({
    required this.directoryProvider,
    required this.fileName,
  });

  File get file => File(p.join(directoryProvider().path, fileName));

  File get _tempFile => File('${file.path}.tmp');

  /// Reads and decodes the JSON file asynchronously.
  ///
  /// Returns `null` if the file does not exist or is empty. Falls back to
  /// synchronous `jsonDecode` when [isolateService] has not been initialized
  /// (e.g. inside unit tests).
  Future<dynamic> readJson() async {
    final File target = file;
    if (!await target.exists()) {
      return null;
    }

    final String raw = await target.readAsString();
    if (raw.trim().isEmpty) {
      return null;
    }

    return decodeJsonString(raw);
  }

  /// Synchronous read fallback for callers that access state before async init.
  dynamic readJsonSync() {
    final File target = file;
    if (!target.existsSync()) {
      return null;
    }
    final String raw = target.readAsStringSync();
    if (raw.trim().isEmpty) {
      return null;
    }
    return jsonDecode(raw);
  }

  /// Encodes [data] and writes it atomically to disk.
  ///
  /// Calls are serialized so that writes always commit in call order.
  Future<void> writeJson(Object data) {
    final Completer<void> completer = Completer<void>();

    _writeChain = _writeChain.then((_) async {
      try {
        final String encoded = await encodeJsonString(data);
        await _writeRawAtomic(encoded);
        completer.complete();
      } catch (e, s) {
        log.error('AtomicJsonStore write failed for $fileName', e, s);
        completer.completeError(e, s);
      }
    });

    return completer.future;
  }

  /// Deletes the backing file and any leftover temp file.
  Future<void> delete() {
    final Completer<void> completer = Completer<void>();

    _writeChain = _writeChain.then((_) async {
      try {
        final File target = file;
        if (await target.exists()) {
          await target.delete();
        }
        final File tmp = _tempFile;
        if (await tmp.exists()) {
          await tmp.delete();
        }
        completer.complete();
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });

    return completer.future;
  }

  Future<void> _writeRawAtomic(String content) async {
    final Directory dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final File tmp = _tempFile;
    final File target = file;

    try {
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(target.path);
    } catch (_) {
      // Clean up temporary file if write/rename failed.
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Decodes a JSON string off the UI thread when [isolateService] is active.
  static Future<dynamic> decodeJsonString(String raw) async {
    if (isolateService.isInitialized) {
      return isolateService.jsonDecodeAsync(raw);
    }
    return jsonDecode(raw);
  }

  /// Encodes a JSON object off the UI thread when [isolateService] is active.
  static Future<String> encodeJsonString(Object data) async {
    if (isolateService.isInitialized) {
      return isolateService.jsonEncodeAsync(data);
    }
    return jsonEncode(data);
  }
}
