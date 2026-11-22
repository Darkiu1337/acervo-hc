import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/pages/popular/popular_page_logic.dart';
import 'package:acervo_hc/src/pages/popular/popular_page_state.dart';

import '../base/base_page.dart';

class PopularPage extends BasePage {
  const PopularPage({
    Key? key,
    bool showMenuButton = false,
    bool showTitle = false,
    String? name,
  }) : super(
          key: key,
          showMenuButton: showMenuButton,
          showTitle: showTitle,
          showJumpButton: false,
          showFilterButton: true,
          showScroll2TopButton: true,
          name: name,
        );

  @override
  PopularPageLogic get logic => Get.put<PopularPageLogic>(PopularPageLogic(), permanent: true);

  @override
  PopularPageState get state => Get.find<PopularPageLogic>().state;

  @override
  List<Widget> buildAppBarActions() {
    final bool active = state.clientFilter.isActive;
    return [
      IconButton(
        tooltip: 'clientFilter'.tr,
        icon: Icon(
          active ? Icons.filter_alt : Icons.filter_alt_outlined,
          size: 26,
          color: active ? Get.theme.colorScheme.primary : null,
        ),
        onPressed: logic.handleTapFilterButton,
      ),
    ];
  }
}
