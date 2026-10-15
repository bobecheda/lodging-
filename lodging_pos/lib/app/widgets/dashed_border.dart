import 'package:flutter/material.dart';

/// Paints a dashed rounded-rectangle border around its child (the "needs
/// cleaning" tile and the logo placeholder). Flutter has no dashed border.
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.color,
    required this.radius,
    required this.child,
    this.width = 1.5,
    this.dash = 5,
    this.gap = 4,
  });

  final Color color;
  final double radius;
  final double width;
  final double dash;
  final double gap;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashedPainter(color, radius, width, dash, gap),
    child: child,
  );
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter(
    this.color,
    this.radius,
    this.width,
    this.dash,
    this.gap,
  );

  final Color color;
  final double radius;
  final double width;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = width / 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - width, size.height - width),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.width != width ||
      old.dash != dash ||
      old.gap != gap;
}
