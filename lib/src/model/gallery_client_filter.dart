import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_tag.dart';

/// Client-side filter for pages where E-Hentai has no native filter UI
/// (Popular and Ranklist).
class GalleryClientFilter {
  static const List<String> allCategories = <String>[
    'Doujinshi',
    'Manga',
    'Artist CG',
    'Game CG',
    'Western',
    'Non-H',
    'Image Set',
    'Cosplay',
    'Asian Porn',
    'Misc',
  ];

  static const List<String> commonLanguages = <String>[
    'portuguese',
    'english',
    'japanese',
    'chinese',
    'spanish',
    'korean',
  ];

  final String keyword;
  final Set<String> disabledCategories;
  final String? language;

  const GalleryClientFilter({
    this.keyword = '',
    this.disabledCategories = const <String>{},
    this.language,
  });

  bool get isActive =>
      keyword.trim().isNotEmpty ||
      disabledCategories.isNotEmpty ||
      (language != null && language!.trim().isNotEmpty);

  GalleryClientFilter copyWith({
    String? keyword,
    Set<String>? disabledCategories,
    String? language,
    bool clearLanguage = false,
  }) {
    return GalleryClientFilter(
      keyword: keyword ?? this.keyword,
      disabledCategories: disabledCategories ?? this.disabledCategories,
      language: clearLanguage ? null : (language ?? this.language),
    );
  }

  /// Returns true when [gallery] satisfies all active client-side criteria.
  bool matches(Gallery gallery) {
    if (!isActive) {
      return true;
    }

    if (disabledCategories.isNotEmpty) {
      final String cat = gallery.category.trim().toLowerCase();
      for (final String disabled in disabledCategories) {
        if (disabled.toLowerCase() == cat) {
          return false;
        }
      }
    }

    if (language != null && language!.trim().isNotEmpty) {
      final String wanted = language!.trim().toLowerCase();
      final String galLang = (gallery.language ?? '').trim().toLowerCase();
      bool matchedLang = galLang == wanted;
      if (!matchedLang) {
        final List<GalleryTag>? langTags = gallery.tags['language'];
        if (langTags != null) {
          matchedLang = langTags.any((t) => t.tagData.key.toLowerCase() == wanted);
        }
      }
      if (!matchedLang) {
        return false;
      }
    }

    final String trimmed = keyword.trim();
    if (trimmed.isNotEmpty) {
      final String haystack = _buildHaystack(gallery);
      final List<String> tokens =
          trimmed.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      for (final String token in tokens) {
        if (token.startsWith('-') && token.length > 1) {
          final String excluded = token.substring(1);
          if (haystack.contains(excluded)) {
            return false;
          }
        } else {
          if (!haystack.contains(token)) {
            return false;
          }
        }
      }
    }

    return true;
  }

  List<Gallery> apply(List<Gallery> source) {
    if (!isActive) {
      return List<Gallery>.from(source);
    }
    return source.where(matches).toList();
  }

  static String _buildHaystack(Gallery gallery) {
    final StringBuffer sb = StringBuffer()
      ..write(gallery.title.toLowerCase())
      ..write(' ')
      ..write((gallery.uploader ?? '').toLowerCase())
      ..write(' ')
      ..write(gallery.category.toLowerCase())
      ..write(' ')
      ..write((gallery.language ?? '').toLowerCase());
    for (final MapEntry<String, List<GalleryTag>> entry in gallery.tags.entries) {
      for (final GalleryTag tag in entry.value) {
        sb
          ..write(' ')
          ..write(entry.key.toLowerCase())
          ..write(':')
          ..write(tag.tagData.key.toLowerCase());
        if (tag.tagData.tagName != null && tag.tagData.tagName!.isNotEmpty) {
          sb
            ..write(' ')
            ..write(tag.tagData.tagName!.toLowerCase());
        }
      }
    }
    return sb.toString();
  }
}
