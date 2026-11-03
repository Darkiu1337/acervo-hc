import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/config/ui_config.dart';
import 'package:acervo_hc/src/model/gallery.dart';
import 'package:acervo_hc/src/widget/eh_image.dart';

/// Grid card for an external (Xlecx) gallery.
///
/// Deliberately not [EHGalleryListCard]: that one expects E-H specific fields
/// (a parseable `publishTime`, E-H categories and tag namespaces) which the
/// external source does not provide.
class XlecxCard extends StatelessWidget {
  final Gallery gallery;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onLongPress;

  /// Desktop right-click; receives the cursor position for the context menu.
  final void Function(Offset globalPosition)? onSecondaryTap;

  const XlecxCard({
    Key? key,
    required this.gallery,
    required this.onTap,
    this.isFavorite = false,
    this.onLongPress,
    this.onSecondaryTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
    );
  }
}
