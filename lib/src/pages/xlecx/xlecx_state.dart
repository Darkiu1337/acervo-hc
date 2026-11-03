import 'package:flutter/material.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

class XlecxState {
  final XlecxSearchConfig config = XlecxSearchConfig();

  final List<Gallery> galleries = <Gallery>[];

  int nextPage = 1;

  bool hasMore = true;

  LoadingState loadingState = LoadingState.idle;

  final ScrollController scrollController = ScrollController();

  final TextEditingController searchController = TextEditingController();

  final FocusNode searchFocusNode = FocusNode();

  bool showSuggestions = false;
}
