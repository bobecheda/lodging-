import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Opens [child] in a 440px panel from the right over the dimmed screen
/// (docs/design.md, "Bed panel"). Escape or a tap on the scrim closes it.
Future<void> showSidePanel(
  BuildContext context, {
  required Widget child,
  String barrierLabel = 'Close the panel',
}) {
  final c = LodgingColors.of(context);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: c.scrim,
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: Sizes.bedPanelWidth,
        height: double.infinity,
        child: Material(color: c.white, child: child),
      ),
    ),
  );
}
