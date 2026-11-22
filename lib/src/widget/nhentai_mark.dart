import 'package:flutter/material.dart';

/// Compact brand badge for the dedicated nhentai tab, matching [XlecxMark].
class NHentaiMark extends StatelessWidget {
  static const Color brandColor = Color(0xFFED2553);

  final double size;
  final Color color;

  const NHentaiMark({
    Key? key,
    this.size = 22,
    this.color = brandColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: color, width: size * 0.085),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size * 0.08),
          child: Text(
            'nH',
            style: TextStyle(
              color: color,
              fontSize: size * 0.56,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
