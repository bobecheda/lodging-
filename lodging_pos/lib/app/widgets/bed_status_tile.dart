import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'dashed_border.dart';
import 'focus_ring.dart';

/// How a bed looks on the board (v2 PR 5, docs/ui-redesign-brief.md "Type
/// and components": v2/Bed tile).
enum BedTileStatus {
  ready('Ready'),
  occupied('Occupied'),
  overstay('Overstay'),
  toClean('To clean');

  const BedTileStatus(this.spoken);

  /// What a screen reader says.
  final String spoken;
}

/// One bed (v2/Bed tile): the letter box and one line ("Ready", "Otieno ·
/// Thu", "Kamau · 2 h", "To clean"). Ready is white with a marine border;
/// Occupied quiet marine-tint with the field border; Overstay red; To clean
/// butter with a dashed border. Each has its own fill and border and its own
/// words, so a status is never shown by colour alone. 44 px tall: it's a
/// hit target.
class BedStatusTile extends StatelessWidget {
  const BedStatusTile({
    super.key,
    required this.label,
    required this.text,
    required this.status,
    this.semanticLabel,
    this.onTap,
  });

  /// "A" or "B".
  final String label;

  /// The tile's one line.
  final String text;
  final BedTileStatus status;

  /// What a screen reader hears instead of the short line, e.g. the guest's
  /// full name and paid-until.
  final String? semanticLabel;

  /// Null: the tile isn't interactive and doesn't look it.
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
      Color? border,
    ) = switch (status) {
      BedTileStatus.ready => (c.white, c.ink, c.marineTint, c.marine, c.marine),
      BedTileStatus.occupied => (
        c.marineTint,
        c.ink,
        c.white,
        c.marine,
        c.fieldBorder,
      ),
      BedTileStatus.overstay => (c.red, c.white, c.white, c.redDark, c.redDark),
      // Dashed, painted below.
      BedTileStatus.toClean => (
        c.butter,
        c.butterText,
        c.white,
        c.butterText,
        null,
      ),
    };

    final body = Container(
      height: Sizes.target,
      padding: const EdgeInsets.symmetric(horizontal: Space.x8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.tile),
        border: border == null
            ? null
            : Border.all(
                color: border,
                width: status == BedTileStatus.ready
                    ? Sizes.borderStrong
                    : Sizes.borderThin,
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: letterBg,
              borderRadius: BorderRadius.circular(Radii.badge),
            ),
            child: Text(label, style: t.meta.copyWith(color: letterFg)),
          ),
          const SizedBox(width: Space.x10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.secondary.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );

    final tile = status == BedTileStatus.toClean
        ? DashedBorder(color: c.butterBorder, radius: Radii.tile, child: body)
        : body;
    return Semantics(
      button: onTap != null,
      label: 'Bed $label. ${status.spoken}. ${semanticLabel ?? text}',
      excludeSemantics: true,
      child: onTap == null
          ? tile
          : FocusRing(
              radius: Radii.tile,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(Radii.tile),
                  child: tile,
                ),
              ),
            ),
    );
  }
}
