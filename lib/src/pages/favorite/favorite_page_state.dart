import 'package:acervo_hc/src/routes/routes.dart';

import '../../model/search_config.dart';
import '../base/base_page_state.dart';

class FavoritePageState extends BasePageState {
  @override
  String get route => Routes.favorite;

  @override
  SearchConfig searchConfig = SearchConfig(searchType: SearchType.favorite);

  /// `true` shows the local (Xlecx) favorites instead of the online E-H ones.
  ///
  /// The page opens in local mode when there is no E-H login, so the list is
  /// usable without an account.
  bool localMode = false;
}
