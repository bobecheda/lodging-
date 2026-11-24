import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/theme.dart';

/// The v2 bed panel's frame (PR 5, Figma "Bed panel · states"), shared by
/// the bed panel and the cleaning panel: the head, a line, the scrolling
/// body, a line and the actions at the foot.
class BedPanelFrame extends StatelessWidget {
  const BedPanelFrame({
    super.key,
    required this.head,
    required this.body,
    this.actions = const [],
  });

  final Widget head;
  final List<Widget> body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        Divider(height: 1, thickness: 1, color: c.line),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.x24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: body,
            ),
          ),
        ),
        if (actions.isNotEmpty) ...[
          Divider(height: 1, thickness: 1, color: c.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x24,
              Space.x16,
              Space.x24,
              Space.x20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: actions,
            ),
          ),
        ],
      ],
    );
  }
}

/// A status badge's look in the head.
enum BedPanelStatus { ready, occupied, overstay, toClean, checkedOut }

/// "106 A", "Normal · KES 500 a night" in the category's colour, the status
/// badge and Close (44 px).
class BedPanelHead extends StatelessWidget {
  const BedPanelHead({
    super.key,
    required this.roomNumber,
    required this.bedLabel,
    required this.subtitle,
    required this.colourKey,
    required this.status,
    required this.onClose,
    this.titleKey = const ValueKey('panel.title'),
    this.closeKey = const ValueKey('panel.close'),
  });

  final String roomNumber;
  final String bedLabel;

  /// "Normal · KES 500 a night".
  final String subtitle;

  /// The category's colour key (v2 PR 4).
  final String colourKey;
  final BedPanelStatus status;
  final VoidCallback onClose;
  final Key titleKey;
  final Key closeKey;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final (String label, Color bg, Color fg) = switch (status) {
      BedPanelStatus.ready => ('Ready', c.marineTint, c.marine),
      BedPanelStatus.occupied => ('Occupied', c.marineTint, c.marine),
      BedPanelStatus.overstay => ('Overstay', c.red, c.white),
      BedPanelStatus.toClean => ('To clean', c.butter, c.butterText),
      BedPanelStatus.checkedOut => ('Checked out', c.surface, c.inkSoft),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.x24,
        Space.x16,
        Space.x12,
        Space.x16,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  label: 'Room $roomNumber, Bed $bedLabel',
                  excludeSemantics: true,
                  child: Text(
                    '$roomNumber $bedLabel',
                    key: titleKey,
                    style: t.pageTitle,
                  ),
                ),
                Text(
                  subtitle,
                  style: t.secondary.copyWith(
                    color: c.category(colourKey).text,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x10,
              vertical: Space.x4,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Text(label, style: t.meta.copyWith(color: fg)),
          ),
          const SizedBox(width: Space.x6),
          IconButton(
            key: closeKey,
            tooltip: 'Close',
            onPressed: onClose,
            iconSize: 20,
            constraints: const BoxConstraints.tightFor(
              width: Sizes.target,
              height: Sizes.target,
            ),
            icon: Icon(LucideIcons.x, color: c.ink),
          ),
        ],
      ),
    );
  }
}

enum BannerTone { red, butter }

/// A tinted line at the top of the body: "2 h past 10:00 · paid to Wed 11
/// Nov", "Checked out today 09:40", "Voids the stay and its payments".
class PanelBanner extends StatelessWidget {
  const PanelBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.tone,
  });

  final IconData icon;
  final String text;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final (Color bg, Color fg) = switch (tone) {
      BannerTone.red => (c.redTint, c.redText),
      BannerTone.butter => (c.butterTint, c.butterText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x14,
        vertical: Space.x12,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: Space.x10),
          Expanded(
            child: Text(text, style: t.body.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}
