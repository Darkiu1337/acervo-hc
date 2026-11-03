import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/widget/loading_state_indicator.dart';

import '../base/base_page.dart';
import 'already_read_page_logic.dart';
import 'already_read_page_state.dart';

class AlreadyReadPage extends BasePage {
  AlreadyReadPage({
    Key? key,
    bool showMenuButton = false,
    bool showTitle = false,
    String? name,
  }) : super(
          key: key,
          showMenuButton: showMenuButton,
          showTitle: showTitle,
          showScroll2TopButton: true,
          name: name,
        );

  @override
  AlreadyReadPageLogic get logic => Get.put<AlreadyReadPageLogic>(AlreadyReadPageLogic(), permanent: true);

  @override
  AlreadyReadPageState get state => Get.find<AlreadyReadPageLogic>().state;

  @override
  List<Widget> buildAppBarActions() {
    return [
      if (state.galleries.isNotEmpty)
        IconButton(
          tooltip: 'deleteAll'.tr,
          icon: const Icon(Icons.delete_outline_outlined, size: 27),
          onPressed: logic.handleTapDeleteButton,
        ),
      ...super.buildAppBarActions(),
    ];
  }

  @override
  Widget buildBody(BuildContext context) {
    if (state.galleries.isEmpty && state.loadingState == LoadingState.noData) {
      return _buildEmptyState(context);
    }

    return super.buildBody(context);
  }

  Widget _buildEmptyState(BuildContext context) {
    final Color hintColor = UIConfig.galleryCardTextColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: hintColor),
            const SizedBox(height: 12),
            Text('noAlreadyRead'.tr, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('noAlreadyReadHint'.tr, textAlign: TextAlign.center, style: TextStyle(color: hintColor)),
          ],
        ),
      ),
    );
  }
}
