import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'dashed_border.dart';

/// The dashed "LOGO" box, until a logo is designed.
class LogoPlaceholder extends StatelessWidget {
  const LogoPlaceholder({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return ExcludeSemantics(
      child: DashedBorder(
        color: c.navMuted,
        radius: Radii.control,
        width: 1,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Text('LOGO', style: t.capsLabel.copyWith(color: c.white)),
          ),
        ),
      ),
    );
  }
}

/// Logo + lodging name (+ optional subtitle) on a marine background.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, required this.lodgingName, this.subtitle});

  /// Falls back to "[LODGING NAME]" until first-run setup sets it.
  final String? lodgingName;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final name = (lodgingName?.trim().isEmpty ?? true)
        ? '[LODGING NAME]'
        : lodgingName!;
    return Row(
      children: [
        const LogoPlaceholder(),
        const SizedBox(width: Space.x12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 2,
                style: t.sectionTitle.copyWith(color: c.white),
              ),
              if (subtitle != null)
                Text(subtitle!, style: t.small.copyWith(color: c.navMuted)),
            ],
          ),
        ),
      ],
    );
  }
}
