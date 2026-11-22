import '../../model/gallery.dart';
import '../../model/gallery_client_filter.dart';
import '../../model/search_config.dart';
import '../../routes/routes.dart';
import '../base/base_page_state.dart';

class PopularPageState extends BasePageState {
  @override
  String get route => Routes.popular;

  @override
  SearchConfig searchConfig = SearchConfig(searchType: SearchType.popular);

  GalleryClientFilter clientFilter = const GalleryClientFilter();

  /// Unfiltered copy of fetched galleries so local filter changes apply
  /// instantaneously without re-fetching.
  final List<Gallery> rawGalleries = <Gallery>[];
}
