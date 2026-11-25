import 'package:flutter/material.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/gallery_source.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

class SourceSearchBucket {
  final GallerySource source;
  final List<Gallery> galleries = <Gallery>[];
  LoadingState loadingState = LoadingState.idle;
  String? errorMessage;

  /// Pagination cursors (provider-specific).
  String? ehNextGid;
  int nextPage = 1;
  bool hasMore = false;

  SourceSearchBucket(this.source);

  void reset() {
    galleries.clear();
    loadingState = LoadingState.idle;
    errorMessage = null;
    ehNextGid = null;
    nextPage = 1;
    hasMore = false;
  }
}

class MultiSearchState {
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  String query = '';
  bool hasSearched = false;
  bool hideAlreadyRead = true;

  /// Which providers are enabled for parallel querying.
  final Set<GallerySource> enabledSources = <GallerySource>{
    GallerySource.eh,
    GallerySource.xlecx,
    GallerySource.nhentai,
  };

  /// `null` means the combined "All" tab; non-null selects one provider tab.
  GallerySource? activeTab;

  final Map<GallerySource, SourceSearchBucket> buckets = <GallerySource, SourceSearchBucket>{
    for (final GallerySource s in GallerySource.values) s: SourceSearchBucket(s),
  };

  /// Computed cross-provider matches (`gid -> other sources`).
  Map<int, Set<GallerySource>> crossMatches = <int, Set<GallerySource>>{};
}
