import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:acervo_hc/src/config/ui_config.dart';

import '../model/gallery_tag.dart';

/// Lightweight tag chip rendered across gallery lists and details pages.
///
/// Kept stateless (no per-tag animation controller or [AnimatedSwitcher]) so
/// lists displaying dozens of tags scroll smoothly without allocating hundreds
/// of tickers.
class EHTag extends StatelessWidget {
  final GalleryTag tag;
  final bool addNameSpaceColor;
  final ValueChanged<GalleryTag>? onTap;
  final ValueChanged<GalleryTag>? onSecondaryTap;
  final ValueChanged<GalleryTag>? onLongPress;
  final bool showTagStatus;
  final bool inDeleteMode;

  const EHTag({
    Key? key,
    required this.tag,
    this.addNameSpaceColor = false,
    this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.showTagStatus = false,
    this.inDeleteMode = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final String label = (tag.tagData.tagName ?? tag.tagData.key) +
        (tag.voteStatus == EHTagVoteStatus.up
            ? '↑'
            : tag.voteStatus == EHTagVoteStatus.down
                ? '↓'
                : '');

    Widget child = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        height: 1,
        color: tag.color ?? (addNameSpaceColor ? UIConfig.tagNameSpaceTextColor : UIConfig.ehTagTextColor(context)),
      ),
    );

    if (inDeleteMode) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: UIConfig.ehTagDeleteButtonBackGroundColor(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.close, size: 10),
          ),
        ],
      );
    }

    child = Align(
      /// Assign [widthFactor] so that we can use it in [Wrap] in details page
      widthFactor: 1.0,
      alignment: Alignment.center,
      child: child,
    );

    if (showTagStatus && tag.tagStatus != EHTagStatus.confidence) {
      child = DottedBorder(
        customPath: (size) {
          return Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width, size.height);
        },
        color: UIConfig.ehTagUnderLineColor(context),
        dashPattern: tag.tagStatus == EHTagStatus.skepticism ? const <double>[3, 4] : const <double>[1, 2],
        padding: EdgeInsets.zero,
        strokeCap: tag.tagStatus == EHTagStatus.skepticism ? StrokeCap.round : StrokeCap.butt,
        child: child,
      );
    }

    child = Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: tag.backgroundColor ??
            (addNameSpaceColor
                ? UIConfig.zhTagNameSpaceColor[tag.tagData.key] ?? UIConfig.tagNameSpaceColor[tag.tagData.key] ?? UIConfig.tagNameSpaceColor['default']
                : UIConfig.ehTagBackGroundColor(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );

    if (onTap != null || onSecondaryTap != null || onLongPress != null) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap != null ? () => onTap!(tag) : null,
          onSecondaryTap: onSecondaryTap != null ? () => onSecondaryTap!(tag) : null,
          onLongPress: onLongPress != null
              ? () {
                  Feedback.forLongPress(context);
                  onLongPress!(tag);
                }
              : null,
          child: child,
        ),
      );
    }

    return child;
  }
}
