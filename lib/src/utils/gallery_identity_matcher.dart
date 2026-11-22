import 'dart:math';
import 'dart:typed_data';

import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_history_model.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';

/// 128-bit perceptual gradient hash of a gallery cover (64-bit horizontal dHash
/// + 64-bit vertical dHash, computed from a 9x9 grayscale downsample).
///
/// Stored as four unsigned 32-bit ints so bitwise operations and popcount work
/// identically across all Dart targets without 64-bit sign quirks.
class CoverPerceptualHash {
  final int hHi;
  final int hLo;
  final int vHi;
  final int vLo;

  const CoverPerceptualHash(this.hHi, this.hLo, this.vHi, this.vLo);

  /// Computes a 128-bit dHash from a 9x9 RGBA8888 pixel buffer (324 bytes).
  ///
  /// Returns `null` when the image is effectively flat/low-contrast or has too
  /// little gradient entropy (e.g. solid background or blank placeholder), so
  /// visual matching never fires on uninformative covers.
  static CoverPerceptualHash? fromRgba9x9(Uint8List rgba) {
    if (rgba.length < 9 * 9 * 4) {
      return null;
    }

    final List<int> luma = List<int>.filled(81, 0);
    int minLuma = 255;
    int maxLuma = 0;

    for (int i = 0; i < 81; i++) {
      final int offset = i * 4;
      final int r = rgba[offset];
      final int g = rgba[offset + 1];
      final int b = rgba[offset + 2];
      final int y = (299 * r + 587 * g + 114 * b) ~/ 1000;
      luma[i] = y;
      if (y < minLuma) {
        minLuma = y;
      }
      if (y > maxLuma) {
        maxLuma = y;
      }
    }

    /// Flat/near-solid covers have unreliable gradient directions.
    if (maxLuma - minLuma < 18) {
      return null;
    }

    int hHi = 0;
    int hLo = 0;
    int vHi = 0;
    int vLo = 0;
    int bitIndex = 0;

    for (int y = 0; y < 8; y++) {
      final int rowStart = y * 9;
      final int nextRowStart = (y + 1) * 9;
      for (int x = 0; x < 8; x++) {
        final int cur = luma[rowStart + x];
        final bool hBit = cur > luma[rowStart + x + 1];
        final bool vBit = cur > luma[nextRowStart + x];

        if (bitIndex < 32) {
          final int mask = 1 << bitIndex;
          if (hBit) {
            hLo |= mask;
          }
          if (vBit) {
            vLo |= mask;
          }
        } else {
          final int mask = 1 << (bitIndex - 32);
          if (hBit) {
            hHi |= mask;
          }
          if (vBit) {
            vHi |= mask;
          }
        }
        bitIndex++;
      }
    }

    final CoverPerceptualHash hash = CoverPerceptualHash(hHi, hLo, vHi, vLo);
    return hash.isInformative ? hash : null;
  }

  static CoverPerceptualHash? tryParse(String? hex) {
    if (hex == null || hex.length != 32) {
      return null;
    }

    final int? hHi = int.tryParse(hex.substring(0, 8), radix: 16);
    final int? hLo = int.tryParse(hex.substring(8, 16), radix: 16);
    final int? vHi = int.tryParse(hex.substring(16, 24), radix: 16);
    final int? vLo = int.tryParse(hex.substring(24, 32), radix: 16);
    if (hHi == null || hLo == null || vHi == null || vLo == null) {
      return null;
    }

    final CoverPerceptualHash hash = CoverPerceptualHash(hHi, hLo, vHi, vLo);
    return hash.isInformative ? hash : null;
  }

  String toHex() {
    return '${_hex32(hHi)}${_hex32(hLo)}${_hex32(vHi)}${_hex32(vLo)}';
  }

  /// Ensures both horizontal and vertical gradients have healthy bit entropy
  /// (rejects all-zero, all-one, or single-stripe patterns).
  bool get isInformative {
    final int hBits = _popcount32(hHi) + _popcount32(hLo);
    final int vBits = _popcount32(vHi) + _popcount32(vLo);
    final int total = hBits + vBits;
    return total >= 18 && total <= 110 && hBits >= 6 && hBits <= 58 && vBits >= 6 && vBits <= 58;
  }

  int hammingDistance(CoverPerceptualHash other) {
    return _popcount32(hHi ^ other.hHi) +
        _popcount32(hLo ^ other.hLo) +
        _popcount32(vHi ^ other.vHi) +
        _popcount32(vLo ^ other.vLo);
  }

  static String _hex32(int value) => (value & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

  static int _popcount32(int x) {
    x = x & 0xFFFFFFFF;
    x = x - ((x >> 1) & 0x55555555);
    x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
    return (((x + (x >> 4)) & 0x0F0F0F0F) * 0x01010101) >> 24 & 0x3F;
  }

  @override
  bool operator ==(Object other) {
    return other is CoverPerceptualHash && hHi == other.hHi && hLo == other.hLo && vHi == other.vHi && vLo == other.vLo;
  }

  @override
  int get hashCode => Object.hash(hHi, hLo, vHi, vLo);

  @override
  String toString() => toHex();
}

/// One normalized core-title candidate extracted from a gallery's raw title.
///
/// Bilingual titles such as `My Sexy Dress-Up Darling 9 | Sono Bisque Doll wa H o Suru 9`
/// or `Title A ー Title B` yield multiple variants so either side can match.
class TitleVariant {
  /// Comparable string with chapter/part marker words omitted (e.g. `ep`/`ch`)
  /// while keeping all normalized numbers intact (`07` -> `7`).
  final String comparable;

  /// Same as [comparable] with numeric tokens removed; used to detect sequel
  /// conflicts (`Lust Flight 7` vs `Lust Flight 8`).
  final String baseWithoutNumbers;

  /// Ordered list of integer numbers present in this title variant.
  final List<int> numericSignature;

  /// Meaningful non-numeric tokens for overlap scoring.
  final Set<String> tokens;

  /// Number of words in [comparable].
  final int wordCount;

  /// Character length of [comparable].
  final int charLength;

  const TitleVariant({
    required this.comparable,
    required this.baseWithoutNumbers,
    required this.numericSignature,
    required this.tokens,
    required this.wordCount,
    required this.charLength,
  });

  bool get isDistinctive => wordCount >= 3 || charLength >= 15;

  bool get isVeryDistinctive => wordCount >= 4 && charLength >= 22;
}

/// Normalized, source-aware identity of a gallery used for cross-provider
/// deduplication.
class GalleryIdentity {
  final int gid;
  final GallerySource source;
  final List<TitleVariant> titleVariants;
  final int? pageCount;
  final Set<String> creators;
  final CoverPerceptualHash? coverHash;

  const GalleryIdentity({
    required this.gid,
    required this.source,
    required this.titleVariants,
    required this.pageCount,
    required this.creators,
    this.coverHash,
  });

  GalleryIdentity withCoverHash(CoverPerceptualHash? hash) {
    return GalleryIdentity(
      gid: gid,
      source: source,
      titleVariants: titleVariants,
      pageCount: pageCount,
      creators: creators,
      coverHash: hash,
    );
  }

  factory GalleryIdentity.fromGallery(Gallery gallery, {CoverPerceptualHash? coverHash}) {
    final Set<String> creators = <String>{};

    final List<String> artistTags = gallery.tags['artist']?.map((t) => t.tagData.key).toList() ?? const <String>[];
    final List<String> groupTags = gallery.tags['group']?.map((t) => t.tagData.key).toList() ?? const <String>[];
    for (final String tag in artistTags) {
      _addNormalizedCreator(creators, tag);
    }
    for (final String tag in groupTags) {
      _addNormalizedCreator(creators, tag);
    }

    if (gallery.galleryUrl.source != GallerySource.eh && gallery.uploader != null && gallery.uploader!.isNotEmpty) {
      for (final String part in gallery.uploader!.split(',')) {
        _addNormalizedCreator(creators, part);
      }
    }

    final List<String> rawTitles = <String>[
      gallery.title,
      if (gallery.altTitle != null && gallery.altTitle!.trim().isNotEmpty) gallery.altTitle!,
    ];
    final _ParsedTitle parsed = GalleryIdentityMatcher.parseTitles(rawTitles);
    creators.addAll(parsed.creators);

    return GalleryIdentity(
      gid: gallery.gid,
      source: gallery.galleryUrl.source,
      titleVariants: parsed.variants,
      pageCount: (gallery.pageCount != null && gallery.pageCount! > 0) ? gallery.pageCount : null,
      creators: creators,
      coverHash: coverHash,
    );
  }

  factory GalleryIdentity.fromHistoryModel(GalleryHistoryModel model) {
    final Set<String> creators = <String>{};

    for (final String rawTag in model.tags) {
      final int sep = rawTag.indexOf(':');
      if (sep <= 0) {
        continue;
      }
      final String namespace = rawTag.substring(0, sep).trim().toLowerCase();
      if (namespace == 'artist' || namespace == 'group') {
        _addNormalizedCreator(creators, rawTag.substring(sep + 1));
      }
    }

    if (model.galleryUrl.source != GallerySource.eh && model.uploader.isNotEmpty) {
      for (final String part in model.uploader.split(',')) {
        _addNormalizedCreator(creators, part);
      }
    }

    final List<String> rawTitles = <String>[
      model.title,
      if (model.altTitle != null && model.altTitle!.trim().isNotEmpty) model.altTitle!,
    ];
    final _ParsedTitle parsed = GalleryIdentityMatcher.parseTitles(rawTitles);
    creators.addAll(parsed.creators);

    return GalleryIdentity(
      gid: model.galleryUrl.gid,
      source: model.galleryUrl.source,
      titleVariants: parsed.variants,
      pageCount: model.pageCount > 0 ? model.pageCount : null,
      creators: creators,
      coverHash: CoverPerceptualHash.tryParse(model.coverHash),
    );
  }

  static void _addNormalizedCreator(Set<String> target, String raw) {
    final String normalized = GalleryIdentityMatcher.normalizeCreator(raw);
    if (normalized.isNotEmpty) {
      target.add(normalized);
    }
  }
}

enum GalleryMatchReason {
  strongCoverHash,
  exactTitleAndCreator,
  exactTitleAndCoverHash,
  exactDistinctiveTitleAndPageCount,
  exactVeryDistinctiveTitle,
  fuzzyTitleAndCreator,
  fuzzyTitleAndCoverHash,
}

class GalleryMatchResult {
  final GalleryMatchReason reason;
  final int? coverDistance;

  const GalleryMatchResult({
    required this.reason,
    this.coverDistance,
  });
}

class _ParsedTitle {
  final List<TitleVariant> variants;
  final Set<String> creators;

  const _ParsedTitle(this.variants, this.creators);
}

/// Multi-signal matcher that identifies the same gallery across E-Hentai /
/// ExHentai and Xlecx while avoiding false positives (sequels, short generic
/// titles, compilations with different page counts).
class GalleryIdentityMatcher {
  /// Maximum Hamming distance (out of 128 bits) for a standalone visual cover
  /// match when page counts are compatible.
  static const int strongCoverDistanceThreshold = 14;

  /// Stricter Hamming distance when page count is unknown or creators disagree.
  static const int ultraStrongCoverDistanceThreshold = 10;

  /// Maximum Hamming distance when corroborated by a title match.
  static const int corroboratedCoverDistanceThreshold = 22;

  static final RegExp _squareBracketRegExp = RegExp(r'\[([^\[\]]+)\]|\u3010([^\u3010\u3011]+)\u3011');
  static final RegExp _parenInsideBracketRegExp = RegExp(r'\(([^()]+)\)');
  static final RegExp _meaningfulParenRegExp = RegExp(
    r'[\(\uFF08]\s*(?:(?:part|pt|vol|volume|ch|chapter|ep|episode|#)\s*\.?\s*)?(\d{1,4}|(?:i{1,3}|iv|vi{0,3}|ix|x{1,2}))\s*[\)\uFF09]',
    caseSensitive: false,
  );
  static final RegExp _allBracketsRegExp = RegExp(
    r'\[[^\[\]]*\]|\([^()]*\)|\{[^{}]*\}|\u3010[^\u3010\u3011]*\u3011|\uFF08[^\uFF08\uFF09]*\uFF09',
  );
  static final RegExp _bilingualSplitRegExp = RegExp(r'\s*\|\s*|\s+[\u30FC\u2014\u2015]\s+|\s+/\s+');
  static final RegExp _apostropheRegExp = RegExp(r"[\u2019\u2018'`\u00B4]");
  static final RegExp _nonWordRegExp = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final RegExp _eventCodeRegExp = RegExp(
    r'^(?:c\d{2,3}|comiket\s*\d*|comic1.*|reitaisai.*|sc\d+|air\s*comiket.*|ff\d+|pf\d+|sunshine\s*creation.*)$',
    caseSensitive: false,
  );

  static const Set<String> _noiseBracketTokens = <String>{
    'english',
    'eng',
    'en',
    'chinese',
    'chi',
    'cn',
    '中文',
    '中国翻訳',
    '中国翻译',
    '漢化',
    '汉化',
    '翻譯',
    '翻译',
    '翻訳',
    '英訳',
    '英译',
    '繁體',
    '简体',
    '繁体',
    'japanese',
    'jpn',
    'jp',
    '日本語',
    'korean',
    'kor',
    'kr',
    '한국어',
    '번역',
    'portuguese',
    'portugues',
    'pt',
    'pt br',
    'brazilian portuguese',
    'spanish',
    'espanol',
    'esp',
    'es',
    'russian',
    'русский',
    'rus',
    'ru',
    'french',
    'francais',
    'fr',
    'german',
    'deutsch',
    'de',
    'italian',
    'italiano',
    'it',
    'ukrainian',
    'ua',
    'thai',
    'vietnamese',
    'tieng viet',
    'polish',
    'indonesian',
    'translated',
    'translation',
    'ai translated',
    'machine translated',
    'mtl',
    'rewrite',
    'digital',
    'デジタル',
    'dl',
    'dl版',
    'decensored',
    'uncensored',
    'censored',
    '無修正',
    '无修正',
    '無修',
    '无修',
    '修正',
    'complete',
    'completed',
    'ongoing',
    'incomplete',
    'wip',
    'color',
    'colored',
    'colorized',
    'full color',
    'textless',
    'no text',
    'ai generated',
    'hq',
    'hd',
    'raw',
    'scan',
    'original',
    'reupload',
    'fixed',
    'v2',
    'v3',
    'final',
    'patreon',
    'fanbox',
    'fantia',
    'pixiv',
    'gumroad',
    'subscribestar',
    'kofi',
    'ko fi',
    '3d',
    'cg',
    'webtoon',
    'comic',
    'manga',
    'doujinshi',
    'anthology',
    'oneshot',
    'one shot',
    'various',
    'unknown',
    'n a',
  };

  static final RegExp _scanlatorGroupRegExp = RegExp(
    r'(?:漢化|汉化|翻譯|翻译|翻訳|번역|\btranslations?\b|\bscanlations?\b|\bscans\b|\btl\b)',
    caseSensitive: false,
  );

  static final RegExp _latinLetterRegExp = RegExp(r'[a-z]');

  static const Set<String> _chapterMarkerWords = <String>{
    'ep',
    'episode',
    'ch',
    'chap',
    'chapter',
    'pt',
    'part',
    'vol',
    'volume',
    'no',
    'num',
    'issue',
    'book',
  };

  static const Map<String, int> _romanNumerals = <String, int>{
    'i': 1,
    'ii': 2,
    'iii': 3,
    'iv': 4,
    'v': 5,
    'vi': 6,
    'vii': 7,
    'viii': 8,
    'ix': 9,
    'x': 10,
    'xi': 11,
    'xii': 12,
    'xiii': 13,
    'xiv': 14,
    'xv': 15,
    'xvi': 16,
    'xvii': 17,
    'xviii': 18,
    'xix': 19,
    'xx': 20,
  };

  /// Returns `true` when two page counts are close enough to represent the same
  /// work (allowing a small delta for cover / translator credit pages).
  ///
  /// When either page count is unknown (`null` or `<= 0`), returns `true`.
  static bool arePageCountsCompatible(int? a, int? b) {
    if (a == null || a <= 0 || b == null || b <= 0) {
      return true;
    }
    final int minPages = min(a, b);
    final int diff = (a - b).abs();
    final int allowedDiff;
    if (minPages <= 5) {
      allowedDiff = 1;
    } else if (minPages <= 20) {
      allowedDiff = 2;
    } else {
      allowedDiff = min(10, max(2, (minPages * 0.08).round()));
    }
    return diff <= allowedDiff;
  }

  /// Evaluates whether two distinct galleries (same or different provider, any
  /// language edition) represent the same work. Returns `null` when they do not
  /// match.
  static GalleryMatchResult? match(GalleryIdentity a, GalleryIdentity b) {
    if (a.gid == b.gid) {
      return null;
    }

    final bool bothPageCountsKnown = a.pageCount != null && b.pageCount != null;
    if (!arePageCountsCompatible(a.pageCount, b.pageCount)) {
      return null;
    }

    if (_hasSequelConflict(a.titleVariants, b.titleVariants)) {
      return null;
    }

    final bool creatorMatch = _creatorsOverlap(a.creators, b.creators);
    final bool creatorContradiction =
        a.creators.isNotEmpty && b.creators.isNotEmpty && !creatorMatch && !_areScriptsDisjoint(a.creators, b.creators);

    final int? coverDistance =
        (a.coverHash != null && b.coverHash != null) ? a.coverHash!.hammingDistance(b.coverHash!) : null;

    /// Tier 2 visual confirmation: an identical or near-identical 128-bit
    /// cover gradient hash with compatible page count works even when titles
    /// are in completely different languages (0% string overlap).
    if (coverDistance != null) {
      final int threshold =
          (bothPageCountsKnown && !creatorContradiction) ? strongCoverDistanceThreshold : ultraStrongCoverDistanceThreshold;
      if (coverDistance <= threshold) {
        return GalleryMatchResult(reason: GalleryMatchReason.strongCoverHash, coverDistance: coverDistance);
      }
    }

    /// Tier 1 exact normalized core-title variant match + corroboration.
    final TitleVariant? exactVariant = _findExactTitleVariant(a.titleVariants, b.titleVariants);
    if (exactVariant != null) {
      if (creatorMatch) {
        return GalleryMatchResult(reason: GalleryMatchReason.exactTitleAndCreator, coverDistance: coverDistance);
      }
      if (coverDistance != null && coverDistance <= corroboratedCoverDistanceThreshold) {
        return GalleryMatchResult(reason: GalleryMatchReason.exactTitleAndCoverHash, coverDistance: coverDistance);
      }
      if (!creatorContradiction) {
        if (bothPageCountsKnown && exactVariant.isDistinctive) {
          return GalleryMatchResult(reason: GalleryMatchReason.exactDistinctiveTitleAndPageCount, coverDistance: coverDistance);
        }
        if (!bothPageCountsKnown && exactVariant.isVeryDistinctive) {
          return GalleryMatchResult(reason: GalleryMatchReason.exactVeryDistinctiveTitle, coverDistance: coverDistance);
        }
      }
    }

    /// High token-overlap match (minor wording variations, identical numeric
    /// signature) ONLY when corroborated by creator or cover hash.
    if (!creatorContradiction && (creatorMatch || (coverDistance != null && coverDistance <= corroboratedCoverDistanceThreshold))) {
      if (_hasHighTokenOverlap(a.titleVariants, b.titleVariants)) {
        return GalleryMatchResult(
          reason: creatorMatch ? GalleryMatchReason.fuzzyTitleAndCreator : GalleryMatchReason.fuzzyTitleAndCoverHash,
          coverDistance: coverDistance,
        );
      }
    }

    return null;
  }

  /// True when one creator set only has Latin characters (e.g. Romaji) and the
  /// other only has non-Latin characters (e.g. Kanji/Kana/Hanzi/Hangul), so a
  /// transliterated artist name is not treated as a contradiction.
  static bool _areScriptsDisjoint(Set<String> a, Set<String> b) {
    final bool aHasLatin = a.any(_latinLetterRegExp.hasMatch);
    final bool bHasLatin = b.any(_latinLetterRegExp.hasMatch);
    return aHasLatin != bHasLatin;
  }

  static _ParsedTitle parseTitles(List<String> rawTitles) {
    final Set<String> creators = <String>{};
    final List<TitleVariant> variants = <TitleVariant>[];
    final Set<String> seenComparables = <String>{};

    for (final String raw in rawTitles) {
      if (raw.trim().isEmpty) {
        continue;
      }

      /// 1. Extract bracketed creator candidates from `[Circle (Artist)]` / `[Artist]`.
      for (final Match match in _squareBracketRegExp.allMatches(raw)) {
        final String content = (match.group(1) ?? match.group(2) ?? '').trim();
        if (content.isEmpty) {
          continue;
        }
        _extractCreatorsFromBracket(content, creators);
      }

      /// 2. Preserve meaningful chapter/part parentheticals like `(Part 2)` or `(2)`
      ///    before stripping metadata brackets.
      String stripped = raw.replaceAllMapped(_meaningfulParenRegExp, (Match m) => ' ${m.group(1)} ');

      /// Repeatedly strip bracketed metadata blocks (handles nested brackets).
      String previous;
      do {
        previous = stripped;
        stripped = stripped.replaceAll(_allBracketsRegExp, ' ');
      } while (stripped != previous);

      /// 3. Split bilingual / dual titles (`Title A | Title B`, `Title A ー Title B`).
      final List<String> segments = stripped
          .split(_bilingualSplitRegExp)
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();

      for (final String segment in segments) {
        final TitleVariant? variant = _buildVariant(segment);
        if (variant != null && seenComparables.add(variant.comparable)) {
          variants.add(variant);
        }
      }

      if (segments.length > 1) {
        final TitleVariant? combined = _buildVariant(segments.join(' '));
        if (combined != null && seenComparables.add(combined.comparable)) {
          variants.add(combined);
        }
      }
    }

    return _ParsedTitle(variants, creators);
  }

  static void _extractCreatorsFromBracket(String content, Set<String> creators) {
    /// Inside `[Circle (Artist)]`, extract both the inner `(Artist)` and the outer `Circle`.
    for (final Match inner in _parenInsideBracketRegExp.allMatches(content)) {
      final String innerText = (inner.group(1) ?? '').trim();
      for (final String part in innerText.split(RegExp(r'[,&、]'))) {
        final String norm = normalizeCreator(part);
        if (_isPlausibleCreator(norm)) {
          creators.add(norm);
        }
      }
    }

    final String outer = content.replaceAll(_parenInsideBracketRegExp, ' ').trim();
    for (final String part in outer.split(RegExp(r'[,、]'))) {
      final String norm = normalizeCreator(part);
      if (_isPlausibleCreator(norm)) {
        creators.add(norm);
      }
    }
  }

  static bool _isPlausibleCreator(String normalized) {
    if (normalized.length < 2) {
      return false;
    }
    if (_noiseBracketTokens.contains(normalized)) {
      return false;
    }
    if (_scanlatorGroupRegExp.hasMatch(normalized)) {
      return false;
    }
    if (_eventCodeRegExp.hasMatch(normalized)) {
      return false;
    }
    if (RegExp(r'^\d+$').hasMatch(normalized)) {
      return false;
    }
    return true;
  }

  static String normalizeCreator(String raw) {
    final String folded = _foldText(raw).replaceAll(_apostropheRegExp, '');
    final String cleaned = folded.replaceAll(_nonWordRegExp, ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
    return cleaned;
  }

  static TitleVariant? _buildVariant(String segment) {
    String text = _foldText(segment);
    text = text.replaceAll('&', ' and ');
    text = text.replaceAll(_apostropheRegExp, '');
    text = text.replaceAll(_nonWordRegExp, ' ').trim();
    if (text.isEmpty) {
      return null;
    }

    final List<String> rawTokens = text.split(RegExp(r'\s+')).where((String t) => t.isNotEmpty).toList();
    if (rawTokens.isEmpty) {
      return null;
    }

    final List<String> comparableTokens = <String>[];
    final List<String> nonNumericList = <String>[];
    final List<int> numericSignature = <int>[];

    for (int i = 0; i < rawTokens.length; i++) {
      final String token = rawTokens[i];
      final String? prev = i > 0 ? rawTokens[i - 1] : null;
      final String? next = i + 1 < rawTokens.length ? rawTokens[i + 1] : null;

      /// Skip chapter marker words (`ep`, `ch`, `part`, `vol`) when immediately
      /// followed by a number or roman numeral so `Ep. 4` == `Ch. 4` == `4`.
      if (_chapterMarkerWords.contains(token) && next != null && (_isDigits(next) || _romanNumerals.containsKey(next))) {
        continue;
      }

      if (_isDigits(token)) {
        final int? parsed = int.tryParse(token);
        if (parsed != null) {
          numericSignature.add(parsed);
          comparableTokens.add(parsed.toString());
          continue;
        }
      }

      /// Convert Roman numerals when preceded by a chapter marker, or `II..XX`
      /// at the end of a title (never convert standalone pronoun `I`).
      final int? roman = _romanNumerals[token];
      if (roman != null) {
        final bool afterMarker = prev != null && _chapterMarkerWords.contains(prev);
        final bool trailingNonI = token != 'i' && i == rawTokens.length - 1;
        if (afterMarker || trailingNonI) {
          numericSignature.add(roman);
          comparableTokens.add(roman.toString());
          continue;
        }
      }

      comparableTokens.add(token);
      nonNumericList.add(token);
    }

    if (comparableTokens.isEmpty) {
      return null;
    }

    final String comparable = comparableTokens.join(' ');
    final String baseWithoutNumbers = nonNumericList.join(' ');
    return TitleVariant(
      comparable: comparable,
      baseWithoutNumbers: baseWithoutNumbers,
      numericSignature: numericSignature,
      tokens: nonNumericList.toSet(),
      wordCount: comparableTokens.length,
      charLength: comparable.length,
    );
  }

  static bool _isDigits(String value) {
    if (value.isEmpty) {
      return false;
    }
    for (int i = 0; i < value.length; i++) {
      final int c = value.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) {
        return false;
      }
    }
    return true;
  }

  static bool _hasSequelConflict(List<TitleVariant> aVariants, List<TitleVariant> bVariants) {
    for (final TitleVariant va in aVariants) {
      if (va.baseWithoutNumbers.isEmpty) {
        continue;
      }
      for (final TitleVariant vb in bVariants) {
        if (vb.baseWithoutNumbers.isEmpty) {
          continue;
        }
        if (_intListsEqual(va.numericSignature, vb.numericSignature)) {
          continue;
        }
        if (va.baseWithoutNumbers == vb.baseWithoutNumbers) {
          return true;
        }
        if (va.tokens.length >= 2 && vb.tokens.length >= 2 && _diceSimilarity(va.tokens, vb.tokens) >= 0.85) {
          return true;
        }
      }
    }
    return false;
  }

  static TitleVariant? _findExactTitleVariant(List<TitleVariant> aVariants, List<TitleVariant> bVariants) {
    TitleVariant? best;
    for (final TitleVariant va in aVariants) {
      for (final TitleVariant vb in bVariants) {
        if (va.comparable == vb.comparable && _intListsEqual(va.numericSignature, vb.numericSignature)) {
          if (best == null || va.charLength > best.charLength) {
            best = va;
          }
        }
      }
    }
    return best;
  }

  static bool _hasHighTokenOverlap(List<TitleVariant> aVariants, List<TitleVariant> bVariants) {
    for (final TitleVariant va in aVariants) {
      if (va.tokens.length < 3) {
        continue;
      }
      for (final TitleVariant vb in bVariants) {
        if (vb.tokens.length < 3) {
          continue;
        }
        if (!_intListsEqual(va.numericSignature, vb.numericSignature)) {
          continue;
        }
        final int intersection = _intersectionCount(va.tokens, vb.tokens);
        if (intersection >= 3 && _diceSimilarity(va.tokens, vb.tokens) >= 0.85) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _creatorsOverlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    for (final String ca in a) {
      if (b.contains(ca)) {
        return true;
      }
      if (ca.length >= 5) {
        for (final String cb in b) {
          if (cb.length >= 5 && (ca.contains(cb) || cb.contains(ca))) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static int _intersectionCount(Set<String> a, Set<String> b) {
    final Set<String> small = a.length <= b.length ? a : b;
    final Set<String> large = identical(small, a) ? b : a;
    int count = 0;
    for (final String item in small) {
      if (large.contains(item)) {
        count++;
      }
    }
    return count;
  }

  static double _diceSimilarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }
    return (2.0 * _intersectionCount(a, b)) / (a.length + b.length);
  }

  static bool _intListsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// Lowercases, converts full-width ASCII to ASCII, and folds common Latin
  /// diacritics so titles match across encodings.
  static String _foldText(String input) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      int code = input.codeUnitAt(i);

      /// Full-width ASCII variants (`！`..`～`) -> ASCII (`!`..`~`).
      if (code >= 0xFF01 && code <= 0xFF5E) {
        code -= 0xFEE0;
      } else if (code == 0x3000) {
        code = 0x20;
      }

      final String ch = String.fromCharCode(code).toLowerCase();
      buffer.write(_diacriticMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  static const Map<String, String> _diacriticMap = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
    'æ': 'ae',
    'ç': 'c', 'ć': 'c', 'č': 'c',
    'ď': 'd', 'đ': 'd',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
    'ł': 'l',
    'ñ': 'n', 'ń': 'n', 'ň': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
    'œ': 'oe',
    'ř': 'r',
    'ś': 's', 'š': 's', 'ş': 's', 'ß': 'ss',
    'ť': 't',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u',
    'ý': 'y', 'ÿ': 'y',
    'ź': 'z', 'ż': 'z', 'ž': 'z',
  };
}
