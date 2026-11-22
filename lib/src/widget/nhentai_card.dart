import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/widget/eh_image.dart';

/// Grid card for an nhentai gallery, mirroring [XlecxCard] with favorites count
/// and direct numeric code metadata.
class NHentaiCard extends StatelessWidget {
  final Gallery gallery;
  final int numFavorites;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onLongPress;
  final void Function(Offset globalPosition)? onSecondaryTap;

  const NHentaiCard({
    Key? key,
    required this.gallery,
    this.numFavorites = 0,
    required this.onTap,
    this.isFavorite = false,
    this.onLongPress,
    this.onSecondaryTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTapDown: onSecondaryTap == null ? null : (TapDownDetails details) => onSecondaryTap!(details.globalPosition),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: EHImage(
                      galleryImage: gallery.cover,
                      autoLayout: true,
                      fit: BoxFit.cover,
                      containerColor: UIConfig.galleryCardBackGroundColor(context),
                      borderRadius: BorderRadius.circular(10),
                      maxBytes: 384 * 1024,
                      loadingWidgetBuilder: () => const SizedBox.shrink(),
                    ),
                  ),
                  if (isFavorite)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.favorite, size: 14, color: Colors.redAccent),
                        ),
                      ),
                    ),
                  if (numFavorites > 0)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.favorite, size: 10, color: Color(0xFFED2553)),
                              const SizedBox(width: 3),
                              Text(
                                _formatCompact(numFavorites),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              gallery.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.2),
            ),
            if (gallery.pageCount != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${gallery.pageCount} ${'pageCount'.tr}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: UIConfig.galleryCardTextColor(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatCompact(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }
}
