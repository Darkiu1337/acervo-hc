import '../../model/gallery.dart';
import '../../model/gallery_client_filter.dart';
import '../../routes/routes.dart';
import '../base/old_base_page_state.dart';

enum RanklistType {
  allTime,
  year,
  month,
  day,
}

class RanklistPageState extends OldBasePageState {
  @override
  String get route => Routes.ranklist;

  RanklistType ranklistType = RanklistType.day;

  GalleryClientFilter clientFilter = const GalleryClientFilter();

  final List<Gallery> rawGalleries = <Gallery>[];
}
