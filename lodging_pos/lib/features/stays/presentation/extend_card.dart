import 'package:flutter/material.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../core/clock/nairobi.dart';
import '../../receipts/presentation/receipt_view.dart';
import '../data/extend_repository.dart';

/// After an extension (FD-7): the new checkout and its receipt, with Print.
/// The Extend form itself is the bed panel's extend state (v2 PR 5).
class ExtendedView extends StatelessWidget {
  const ExtendedView({super.key, required this.result, required this.onDone});

  final ExtendResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final nights =
        '${result.nights} ${result.nights == 1 ? 'night' : 'nights'}';
    return Column(
      key: const ValueKey('extend.result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.marine, size: 24),
            const SizedBox(width: Space.x8),
            Expanded(
              child: Text(
                'Extended by $nights',
                key: const ValueKey('extend.result.title'),
                style: t.sectionTitle,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x4),
        Text(
          'New checkout ${formatDayDateComma(result.newPaidUntil)}.',
          key: const ValueKey('extend.result.checkout'),
          style: t.body.copyWith(color: c.inkSoft),
        ),
        const SizedBox(height: Space.x16),
        ReceiptPanel(paymentId: result.paymentId),
        const SizedBox(height: Space.x20),
        AppButton.secondary(
          key: const ValueKey('extend.done'),
          label: 'Done',
          onPressed: onDone,
        ),
      ],
    );
  }
}
