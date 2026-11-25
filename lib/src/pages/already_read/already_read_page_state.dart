import 'package:flutter/material.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';

import '../../routes/routes.dart';
import '../base/old_base_page_state.dart';

class AlreadyReadPageState extends OldBasePageState {
  @override
  String get route => Routes.alreadyRead;

  GalleryClientFilter clientFilter = const GalleryClientFilter();

  int totalStoredCount = 0;
  int filteredTotalCount = 0;

  final TextEditingController searchController = TextEditingController();
}
