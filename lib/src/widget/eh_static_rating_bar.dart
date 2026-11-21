import 'package:flutter/material.dart';

/// Read-only 5-star rating display for gallery cards.
///
/// Replaces `RatingBar.builder` (a stateful widget with gesture detectors and
/// per-star clipping/value notifiers) on scrollable listing cards where ratings
/// are purely static.
class EHStaticRatingBar extends StatelessWidget {
  final double rating;
  final double itemSize;
  final Color ratedColor;
  final Color unratedColor;

  const EHStaticRatingBar({
    Key? key,
    required this.rating,
    required this.itemSize,
    required this.ratedColor,
    required this.unratedColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final double clamped = rating.clamp(0.0, 5.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(5, (int index) {
        final double diff = clamped - index;
        final IconData icon;
        final Color color;
        if (diff >= 0.75) {
          icon = Icons.star;
          color = ratedColor;
        } else if (diff >= 0.25) {
          icon = Icons.star_half;
          color = ratedColor;
        } else {
          icon = Icons.star;
          color = unratedColor;
        }
        return Icon(icon, size: itemSize, color: color);
      }, growable: false),
    );
  }
}
