import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:acervo_hc/src/enum/config_enum.dart';
import 'package:acervo_hc/src/service/local_config_service.dart';
import 'package:acervo_hc/src/service/log.dart';

/// Which part of an image a reader slot displays.
enum ImagePart {
  whole,

  /// The half read first (right half in RTL / top-to-bottom; left half in LTR).
  first,

  /// The half read second.
  second,
}

/// Returns whether the right half of a split wide page should be shown first.
///
/// Manga / right-to-left and vertical top-to-bottom layouts read right-to-left
/// by default; left-to-right layouts read left-to-right. [reverseOrder] flips
/// the default for Western comics or non-standard scans.
bool showRightHalfFirst({
  required bool isRightToLeftOrVertical,
  required bool reverseOrder,
}) {
  return reverseOrder ? !isRightToLeftOrVertical : isRightToLeftOrVertical;
}

/// Returns whether [part] corresponds to the right half of the image.
bool isRightHalfForPart(
  ImagePart part, {
  required bool rightHalfFirst,
}) {
  if (part == ImagePart.first) {
    return rightHalfFirst;
  }
  return !rightHalfFirst;
}

/// Clips [child] to either its left or right half without re-decoding or
/// duplicating the underlying image texture.
class SplitHalfClipper extends StatelessWidget {
  final Widget child;
  final bool showRightHalf;

  const SplitHalfClipper({
    Key? key,
    required this.child,
    required this.showRightHalf,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: showRightHalf ? Alignment.centerRight : Alignment.centerLeft,
        widthFactor: 0.5,
        child: child,
      ),
    );
  }
}

/// Persisted wide-page (spread) flags for the book currently open in the
/// reader (`width > height`). Shared under [ConfigEnum.isSpreadPage] so
/// reopening a book already knows which pages are spreads before decoding.
class SpreadPages {
  final String storageKey;
  final int imageCount;

  late List<bool> _flags;
  final Completer<void> _loaded = Completer<void>();

  SpreadPages({
    required this.storageKey,
    required this.imageCount,
  }) {
    _flags = List<bool>.filled(imageCount, false, growable: true);
  }

  Future<void> get loaded => _loaded.future;

  bool get isLoaded => _loaded.isCompleted;

  int get length => _flags.length;

  List<bool> get flags => List<bool>.unmodifiable(_flags);

  bool operator [](int index) => index >= 0 && index < _flags.length && _flags[index];

  Future<void> load() async {
    if (_loaded.isCompleted) {
      return;
    }
    try {
      final String? raw = await localConfigService.read(
        configKey: ConfigEnum.isSpreadPage,
        subConfigKey: storageKey,
      );
      if (raw != null) {
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        for (int i = 0; i < decoded.length && i < _flags.length; i++) {
          if (decoded[i] == 1 || decoded[i] == true) {
            _flags[i] = true;
          }
        }
      }
    } catch (e) {
      log.warning('Unreadable spread pages for $storageKey: $e');
    } finally {
      if (!_loaded.isCompleted) {
        _loaded.complete();
      }
    }
  }

  /// Marks [index] as a wide page. Returns true only if this changed the flag.
  bool mark(int index) {
    if (index < 0 || index >= _flags.length || _flags[index]) {
      return false;
    }
    _flags[index] = true;
    unawaited(
      localConfigService.write(
        configKey: ConfigEnum.isSpreadPage,
        subConfigKey: storageKey,
        value: jsonEncode(<int>[for (final bool flag in _flags) flag ? 1 : 0]),
      ),
    );
    return true;
  }
}

/// Maps between reader pages and source images when wide pages are split into
/// two swipeable pages in single-page layouts.
class PageParts {
  final List<bool> _split;
  final List<int> _pageToImage = <int>[];
  final List<ImagePart> _pageToPart = <ImagePart>[];
  final List<int> _imageToFirstPage = <int>[];

  PageParts(List<bool> split) : _split = List<bool>.unmodifiable(split) {
    for (int image = 0; image < split.length; image++) {
      _imageToFirstPage.add(_pageToImage.length);
      if (split[image]) {
        _pageToImage.add(image);
        _pageToPart.add(ImagePart.first);
        _pageToImage.add(image);
        _pageToPart.add(ImagePart.second);
      } else {
        _pageToImage.add(image);
        _pageToPart.add(ImagePart.whole);
      }
    }
  }

  PageParts.unsplit(int imageCount) : this(List<bool>.filled(imageCount, false));

  int get imageCount => _split.length;

  int get pageCount => _pageToImage.length;

  bool isImageSplit(int imageIndex) =>
      imageIndex >= 0 && imageIndex < _split.length && _split[imageIndex];

  int imageOf(int pageIndex) {
    if (_pageToImage.isEmpty) {
      return 0;
    }
    final int clamped = pageIndex.clamp(0, _pageToImage.length - 1).toInt();
    return _pageToImage[clamped];
  }

  ImagePart partOf(int pageIndex) {
    if (_pageToPart.isEmpty) {
      return ImagePart.whole;
    }
    final int clamped = pageIndex.clamp(0, _pageToPart.length - 1).toInt();
    return _pageToPart[clamped];
  }

  int firstPageOf(int imageIndex) {
    if (_imageToFirstPage.isEmpty) {
      return 0;
    }
    final int clamped = imageIndex.clamp(0, _imageToFirstPage.length - 1).toInt();
    return _imageToFirstPage[clamped];
  }

  int secondPageOf(int imageIndex) {
    final int first = firstPageOf(imageIndex);
    return isImageSplit(imageIndex) ? first + 1 : first;
  }
}
