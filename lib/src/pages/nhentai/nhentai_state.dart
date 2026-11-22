import 'package:flutter/material.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/nhentai_gallery.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

class NHentaiCardItem {
  final Gallery gallery;
  final int numFavorites;

  const NHentaiCardItem({
    required this.gallery,
    required this.numFavorites,
  });
}

class NHentaiState {
  NHentaiSort sort = NHentaiSort.recent;
  NHentaiLanguage language = NHentaiLanguage.all;
  String query = '';

  final List<NHentaiCardItem> items = <NHentaiCardItem>[];

  int nextPage = 1;
  bool hasMore = true;
  LoadingState loadingState = LoadingState.idle;

  final ScrollController scrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
}
