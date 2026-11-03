import 'package:flutter/material.dart';

/// Brand mark of https://xlecx.one: a crossed "X" (the site's logo is the word
/// "XlecX" over the dark UI, so the X carries the brand on its own).
class XlecxMark extends StatelessWidget {
  /// Accent used by the site's links and section headers.
  static const Color brandColor = Color(0xFF4C8DFF);

  final double size;
  final Color color;

  const XlecxMark({
    Key? key,
    this.size = 22,
    this.color = brandColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _XlecxMarkPainter(color: color),
      ),
    );
  }
}

class _XlecxMarkPainter extends CustomPainter {
  final Color color;

  const _XlecxMarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..strokeWidth = side * 7 / 32;

    final double inset = side * 5 / 32;
    canvas.drawLine(Offset(inset, inset), Offset(side - inset, side - inset), paint);
    canvas.drawLine(Offset(side - inset, inset), Offset(inset, side - inset), paint);
  }

  @override
  bool shouldRepaint(covariant _XlecxMarkPainter oldDelegate) => oldDelegate.color != color;
}
