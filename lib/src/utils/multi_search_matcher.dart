import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/utils/gallery_identity_matcher.dart';

/// Pure matching & ordering utilities for unified multi-source search across
/// E-Hentai/ExHentai, Xlecx, and nhentai.
class MultiSearchMatcher {
  /// Finds cross-provider equivalences among search results from different
  /// sources using [GalleryIdentityMatcher.match].
  ///
  /// Returns a map `gallery.gid -> Set<GallerySource>` of *other* providers
  /// that also contain a matching work.
  static Map<int, Set<GallerySource>> findCrossProviderMatches(
    Map<GallerySource, List<Gallery>> resultsBySource,
  ) {
    final Map<GallerySource, List<GalleryIdentity>> identities = <GallerySource, List<GalleryIdentity>>{};
    for (final MapEntry<GallerySource, List<Gallery>> entry in resultsBySource.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      identities[entry.key] = entry.value.map((Gallery g) => GalleryIdentity.fromGallery(g)).toList();
    }

    final List<GallerySource> activeSources = identities.keys.toList();
    final Map<int, Set<GallerySource>> matches = <int, Set<GallerySource>>{};

    for (int i = 0; i < activeSources.length; i++) {
      final GallerySource sourceA = activeSources[i];
      final List<GalleryIdentity> listA = identities[sourceA]!;

      for (int j = i + 1; j < activeSources.length; j++) {
        final GallerySource sourceB = activeSources[j];
        final List<GalleryIdentity> listB = identities[sourceB]!;

        for (final GalleryIdentity idA in listA) {
          for (final GalleryIdentity idB in listB) {
            if (GalleryIdentityMatcher.match(idA, idB) != null) {
              (matches[idA.gid] ??= <GallerySource>{}).add(sourceB);
              (matches[idB.gid] ??= <GallerySource>{}).add(sourceA);
            }
          }
        }
      }
    }

    return matches;
  }

  /// Interleaves galleries round-robin across [order] so the combined "All"
  /// view surfaces top results from every provider fairly.
  static List<Gallery> interleaveResults(
    Map<GallerySource, List<Gallery>> resultsBySource, {
    List<GallerySource> order = GallerySource.values,
  }) {
    final List<List<Gallery>> lists = <List<Gallery>>[
      for (final GallerySource source in order)
        if ((resultsBySource[source] ?? const <Gallery>[]).isNotEmpty) resultsBySource[source]!,
    ];
    if (lists.isEmpty) {
      return const <Gallery>[];
    }

    int maxLen = 0;
    for (final List<Gallery> list in lists) {
      if (list.length > maxLen) {
        maxLen = list.length;
      }
    }

    final List<Gallery> combined = <Gallery>[];
    for (int idx = 0; idx < maxLen; idx++) {
      for (final List<Gallery> list in lists) {
        if (idx < list.length) {
          combined.add(list[idx]);
        }
      }
    }
    return combined;
  }
}
