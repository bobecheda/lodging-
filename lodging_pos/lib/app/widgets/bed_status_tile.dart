import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'dashed_border.dart';

/// How a bed looks on the board (docs/design.md, "Bed status styles").
enum BedTileStatus {
  ready('READY', 'Ready'),
  occupied('IN USE', 'In use'),
  overstay('OVERSTAY', 'Overstay'),
  toClean('TO CLEAN', 'Needs cleaning');

  const BedTileStatus(this.badge, this.spoken);

  /// The caps label on the tile.
  final String badge;

  /// What a screen reader says.
  final String spoken;
}

/// One bed: letter box, "Category · KES price", a second line, and the caps
/// status label. Each status has its own background, border style and
/// label, so it is never shown by colour alone.
class BedStatusTile extends StatelessWidget {
  const BedStatusTile({
    super.key,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.status,
    this.onTap,
  });

  /// "A" or "B".
  final String label;

  /// e.g. "Deluxe · KES 700".
  final String title;

  /// e.g. "Ready to let", "Peter Kamau · until 22:15", "paid to 10:00".
  final String subtitle;
  final BedTileStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);

    final (
      Color bg,
      Color fg,
      Color letterBg,
      Color letterFg,
    ) = switch (status) {
      BedTileStatus.ready => (c.white, c.ink, c.marineTint, c.marine),
      BedTileStatus.occupied => (c.marine, c.white, c.marine600, c.white),
      BedTileStatus.overstay => (c.red, c.white, c.redDark, c.white),
      BedTileStatus.toClean => (c.butter, c.butterText, c.white, c.butterText),
    };
    final subtitleColor = switch (status) {
      BedTileStatus.ready => c.muted,
      BedTileStatus.toClean => c.butterText,
      _ => c.navText,
    };

    final badge = status == BedTileStatus.overstay
        ? Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x8,
              vertical: Space.x4,
            ),
            decoration: BoxDecoration(
              color: c.white,
              borderRadius: BorderRadius.circular(Radii.badge),
            ),
            child: Text(
              status.badge,
              style: t.capsLabel.copyWith(color: c.redDark),
            ),
          )
        : Text(
            status.badge,
            style: t.capsLabel.copyWith(
              color: status == BedTileStatus.ready ? c.marine : fg,
            ),
          );

    final body = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x12,
        vertical: Space.x10,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.tile),
        border: status == BedTileStatus.toClean
            ? null // dashed, painted below
            : Border.all(
                color: status == BedTileStatus.overstay ? c.redDark : c.marine,
                width: Sizes.borderStrong,
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: letterBg,
              borderRadius: BorderRadius.circular(Radii.badge),
            ),
            child: Text(label, style: t.bodyStrong.copyWith(color: letterFg)),
          ),
          const SizedBox(width: Space.x12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: t.bodyStrong.copyWith(color: fg)),
                Text(
                  subtitle,
                  maxLines: 2,
                  style: t.small.copyWith(color: subtitleColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.x8),
          badge,
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: 'Bed $label, $title. ${status.spoken}. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.tile),
          child: status == BedTileStatus.toClean
              ? DashedBorder(
                  color: c.butterBorder,
                  radius: Radii.tile,
                  child: body,
                )
              : body,
        ),
      ),
    );
  }
}
