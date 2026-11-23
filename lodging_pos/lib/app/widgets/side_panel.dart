import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'overlay_route.dart';

/// Opens [child] in a 440px panel from the right over the dimmed screen
/// (docs/design.md, "Bed panel"): it slides in as the scrim fades
/// (`LodgingMotion.panel`, `scrim`). Escape or a tap on the scrim closes
/// it.
Future<void> showSidePanel(
  BuildContext context, {
  required Widget child,
  String barrierLabel = 'Close the panel',
}) {
  final c = LodgingColors.of(context);
  final m = LodgingMotion.of(context);
  return Navigator.of(context).push(
    ShellOverlayRoute<void>(
      label: barrierLabel,
      scrim: c.scrim,
      inDuration: m.panel.duration,
      outDuration: m.panel.duration,
      scrimDuration: m.scrim.duration,
      transition: slideFrom(1, m.panel, m.panel),
      builder: (context) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: Sizes.bedPanelWidth,
          height: double.infinity,
          child: Material(color: c.white, child: child),
        ),
      ),
    ),
  );
}
