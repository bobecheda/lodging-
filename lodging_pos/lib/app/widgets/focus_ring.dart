import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The keyboard focus ring (docs/ui-redesign-brief.md, "Shell states"): a
/// 2 px marine ring drawn 2 px outside [child] while it, or a control
/// inside it, has keyboard focus. Only for the keyboard (Tab key): a mouse
/// click never shows it. Painted outside the child's box, so no parent may
/// clip it.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child, required this.radius});

  final Widget child;

  /// The control's own corner radius; the ring follows it, 2 px out.
  final double radius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  var _focused = false;
  var _keyboard =
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    super.dispose();
  }

  void _onMode(FocusHighlightMode mode) {
    final keyboard = mode == FocusHighlightMode.traditional;
    if (keyboard != _keyboard) setState(() => _keyboard = keyboard);
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: CustomPaint(
        foregroundPainter: FocusRingPainter(
          show: _focused && _keyboard,
          radius: widget.radius,
          color: c.marine,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Paints the ring; public so tests can tell whether it shows.
class FocusRingPainter extends CustomPainter {
  const FocusRingPainter({
    required this.show,
    required this.radius,
    required this.color,
  });

  final bool show;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!show) return;
    const out = Sizes.focusGap + Sizes.focusRing / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(out),
        Radius.circular(radius + out),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = Sizes.focusRing
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter old) =>
      old.show != show || old.radius != radius || old.color != color;
}
