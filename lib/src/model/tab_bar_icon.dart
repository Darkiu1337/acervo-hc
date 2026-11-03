import 'package:flutter/widgets.dart';

enum TabBarIconNameEnum {
  home,
  search,
  popular,
  ranklist,
  watched,
  favorite,
  history,
  download,
  eightMuses,
  setting,
  alreadyRead,

  /// New values must be appended: [PreferenceSetting] stores the index of the
  /// default tab, so inserting in the middle would change existing configs.
  xlecx,
}

class TabBarIcon {
  final TabBarIconNameEnum name;
  final String routeName;
  final Widget selectedIcon;
  final Widget unselectedIcon;
  final ValueGetter<Widget> page;
  final ValueGetter<ScrollController>? scrollController;
  bool shouldRender;
  bool enterNewRoute;

  TabBarIcon({
    required this.name,
    required this.routeName,
    required this.selectedIcon,
    required this.unselectedIcon,
    required this.page,
    this.scrollController,
    required this.shouldRender,
    this.enterNewRoute = false,
  });
}
