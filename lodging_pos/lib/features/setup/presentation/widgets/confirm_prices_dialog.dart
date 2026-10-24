import 'package:flutter/material.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/buttons.dart';
import '../../../../app/widgets/notes.dart';
import '../../domain/prices_settings.dart';

/// Lists every price about to change ("Deluxe: 700 → 750") before saving,
/// and asks "Are you sure?" about any change of more than 50%
/// ([isBigPriceChange]). Pops true on Confirm.
class ConfirmPricesDialog extends StatelessWidget {
  const ConfirmPricesDialog({super.key, required this.changes});

  final List<PriceChange> changes;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return AlertDialog(
      title: Text(
        changes.length == 1 ? 'Save this price?' : 'Save these prices?',
        style: t.sectionTitle,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final change in changes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x4),
                child: Text(
                  change.label,
                  key: ValueKey('confirm.change.${change.categoryId}'),
                  style: t.monoStrong,
                ),
              ),
            for (final change in changes)
              if (change.isBig) ...[
                const SizedBox(height: Space.x8),
                Note.warning(
                  bigPriceChangeQuestion(change),
                  key: ValueKey('confirm.big.${change.categoryId}'),
                ),
              ],
            const SizedBox(height: Space.x16),
            Text(
              'These prices apply to new check-ins only. Guests already '
              'staying keep their price.',
              style: t.body.copyWith(color: c.inkSoft),
            ),
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('confirm.cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          key: const ValueKey('confirm.ok'),
          label: 'Confirm',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
