import 'package:flutter/material.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/labeled_dropdown.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/money/kes.dart';
import '../../domain/bed_category.dart';
import '../../domain/rooms.dart';

/// The white side panel next to a setup table.
class SidePanel extends StatelessWidget {
  const SidePanel({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(title, style: t.sectionTitle)),
            const SizedBox(height: Space.x20),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// "Deluxe · KES 700" options. Only active categories can be chosen; the
/// bed's current category stays listed (disabled) if it has been closed.
List<DropdownOption<String>> categoryOptions(
  List<BedCategory> categories, {
  String? current,
}) => [
  for (final c in categories)
    if (c.isActive || c.id == current)
      DropdownOption(
        c.id,
        c.isActive
            ? '${c.name} · ${formatKes(c.pricePerNight)}'
            : '${c.name} (closed)',
        enabled: c.isActive,
      ),
];

/// A message for the panel's error note, or null when the error is a form
/// error shown on the fields themselves.
String? panelError(Object error) => switch (error) {
  InvalidRoom() => null,
  RoomRuleViolation(:final message) => message,
  NotPermitted() => 'Only the owner can change rooms and beds.',
  _ => 'Could not save: $error',
};

/// The letter box ("A", "B") used beside each bed.
class BedLetter extends StatelessWidget {
  const BedLetter(this.label, {super.key});

  final BedLabel label;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Container(
      width: Sizes.target,
      height: Sizes.target,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.marineTint,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Text(label.code, style: t.sectionTitle.copyWith(color: c.marine)),
    );
  }
}
