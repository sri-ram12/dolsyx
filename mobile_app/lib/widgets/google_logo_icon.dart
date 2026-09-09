import 'dart:math';
import 'package:flutter/material.dart';

class GoogleLogoIcon extends StatelessWidget {
  final double size;
  const GoogleLogoIcon({super.key, this.size = 22.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);
    final double strokeWidth = size.width * 0.22;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final Rect rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Red arc (Top left)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -pi * 0.82, pi * 0.47, false, paint);

    // Yellow arc (Bottom left)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, -pi * 0.35, pi * 0.42, false, paint);

    // Green arc (Bottom right)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, pi * 0.07, pi * 0.45, false, paint);

    // Blue arc (Right top)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, pi * 0.52, pi * 0.38, false, paint);

    // Blue horizontal bar in middle right
    final Paint fillBlue = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    final Rect barRect = Rect.fromLTRB(
      center.dx - strokeWidth * 0.1,
      center.dy - strokeWidth / 2,
      center.dx + radius,
      center.dy + strokeWidth / 2,
    );
    canvas.drawRect(barRect, fillBlue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
