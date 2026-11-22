import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:acervo_hc/src/enum/config_enum.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/service/local_config_service.dart';
import 'package:acervo_hc/src/service/log.dart';

class WatchedBookmark {
  final int gid;
  final String title;
  final String? coverUrl;
  final int createdAtMs;

  const WatchedBookmark({
    required this.gid,
    required this.title,
    this.coverUrl,
    required this.createdAtMs,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'gid': gid,
        'title': title,
        'coverUrl': coverUrl,
        'createdAtMs': createdAtMs,
      };

  factory WatchedBookmark.fromJson(Map<String, dynamic> json) => WatchedBookmark(
        gid: (json['gid'] as num).toInt(),
        title: (json['title'] ?? '').toString(),
        coverUrl: json['coverUrl']?.toString(),
        createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      );
}

/// Tracks which galleries the user has scrolled past or opened in the Watched
/// tab, remembers where they left off, and stores manual Watched bookmarks.
class WatchedProgressService {
  WatchedProgressService._();

  static final WatchedProgressService instance = WatchedProgressService._();

  static const int _maxSeenGids = 2000;
  static const String _subKey = 'state';

  final LinkedHashSet<int> _seenGids = LinkedHashSet<int>();
  final List<WatchedBookmark> _bookmarks = <WatchedBookmark>[];
  WatchedBookmark? _lastAnchor;

  final RxInt revision = 0.obs;
  bool _loaded = false;
  Future<void>? _loadFuture;

  Set<int> get seenGids => UnmodifiableSetView<int>(_seenGids);

  int get seenCount => _seenGids.length;

  WatchedBookmark? get lastAnchor => _lastAnchor;

  List<WatchedBookmark> get bookmarks => List<WatchedBookmark>.unmodifiable(_bookmarks);

  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    if (_loaded) {
      return;
    }
    try {
      final String? raw = await localConfigService.read(
        configKey: ConfigEnum.watchedProgress,
        subConfigKey: _subKey,
      );
      if (raw != null && raw.isNotEmpty) {
        loadFromJsonString(raw);
      }
    } catch (e) {
      log.warning('Failed to load watched progress: $e');
    } finally {
      _loaded = true;
      revision.value++;
    }
  }

  void loadFromJsonString(String raw) {
    final Map<String, dynamic> map = jsonDecode(raw) as Map<String, dynamic>;
    _seenGids.clear();
    final List<dynamic>? seenList = map['seenGids'] as List<dynamic>?;
    if (seenList != null) {
      for (final dynamic item in seenList) {
        if (item is num) {
          _seenGids.add(item.toInt());
        }
      }
    }
    _bookmarks.clear();
    final List<dynamic>? bmList = map['bookmarks'] as List<dynamic>?;
    if (bmList != null) {
      for (final dynamic item in bmList) {
        if (item is Map<String, dynamic>) {
          _bookmarks.add(WatchedBookmark.fromJson(item));
        }
      }
    }
    final dynamic anchor = map['lastAnchor'];
    _lastAnchor = anchor is Map<String, dynamic> ? WatchedBookmark.fromJson(anchor) : null;
  }

  String toJsonString() => jsonEncode(<String, dynamic>{
        'seenGids': _seenGids.toList(),
        'bookmarks': _bookmarks.map((b) => b.toJson()).toList(),
        'lastAnchor': _lastAnchor?.toJson(),
      });

  bool isSeen(int gid) => _seenGids.contains(gid);

  bool isBookmarked(int gid) => _bookmarks.any((b) => b.gid == gid);

  Future<void> markSeen(Iterable<int> gids) async {
    await ensureLoaded();
    bool changed = false;
    for (final int gid in gids) {
      if (_seenGids.add(gid)) {
        changed = true;
      }
    }
    while (_seenGids.length > _maxSeenGids) {
      _seenGids.remove(_seenGids.first);
    }
    if (changed) {
      revision.value++;
      await _persist();
    }
  }

  Future<void> toggleSeen(int gid) async {
    await ensureLoaded();
    if (_seenGids.contains(gid)) {
      _seenGids.remove(gid);
    } else {
      _seenGids.add(gid);
    }
    revision.value++;
    await _persist();
  }

  Future<void> setLastAnchor(Gallery gallery) async {
    await ensureLoaded();
    _seenGids.add(gallery.gid);
    _lastAnchor = WatchedBookmark(
      gid: gallery.gid,
      title: gallery.title,
      coverUrl: gallery.cover.url,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    revision.value++;
    await _persist();
  }

  Future<bool> toggleBookmark(Gallery gallery) async {
    await ensureLoaded();
    final int idx = _bookmarks.indexWhere((b) => b.gid == gallery.gid);
    final bool added;
    if (idx >= 0) {
      _bookmarks.removeAt(idx);
      added = false;
    } else {
      _bookmarks.insert(
        0,
        WatchedBookmark(
          gid: gallery.gid,
          title: gallery.title,
          coverUrl: gallery.cover.url,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      added = true;
    }
    revision.value++;
    await _persist();
    return added;
  }

  Future<void> removeBookmark(int gid) async {
    await ensureLoaded();
    _bookmarks.removeWhere((b) => b.gid == gid);
    revision.value++;
    await _persist();
  }

  Future<void> clearAll() async {
    await ensureLoaded();
    _seenGids.clear();
    _bookmarks.clear();
    _lastAnchor = null;
    revision.value++;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await localConfigService.write(
        configKey: ConfigEnum.watchedProgress,
        subConfigKey: _subKey,
        value: toJsonString(),
      );
    } catch (e) {
      log.warning('Failed to persist watched progress: $e');
    }
  }
}

final WatchedProgressService watchedProgressService = WatchedProgressService.instance;
