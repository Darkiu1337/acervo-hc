import 'package:flutter/material.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';
import 'package:acervo_hc/src/routes/routes.dart';

import '../../model/search_config.dart';
import '../base/base_page_state.dart';

class FavoritePageState extends BasePageState {
  @override
  String get route => Routes.favorite;

  @override
  SearchConfig searchConfig = SearchConfig(searchType: SearchType.favorite);

  /// `true` shows the local (Xlecx / nhentai / offline) favorites instead of
  /// the online E-H ones.
  ///
  /// The page opens in local mode when there is no E-H login, so the list is
  /// usable without an account.
  bool localMode = false;

  /// Active collection filter in local mode (`null` = all collections).
  String? selectedCollection;

  /// Client-side search, source, tag, and sort filter for local favorites.
  GalleryClientFilter localFilter = const GalleryClientFilter();

  int totalLocalCount = 0;

  final TextEditingController localSearchController = TextEditingController();
}
