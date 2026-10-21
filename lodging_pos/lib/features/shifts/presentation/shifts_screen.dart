import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../data/shift_repository.dart';
import '../domain/shift_close.dart';
import 'shift_providers.dart';

/// FD-11, supervisor (and later the owner): every shift on this computer, newest first, with its
/// cash variance ("shown to the supervisor"). A variance over 1% of the shift's
/// takings is highlighted; a recount and a close by someone else are
/// spelled out. Open shifts can be closed from here.
class ShiftsScreen extends ConsumerWidget {
  const ShiftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LodgingType.of(context);
    final list = ref.watch(shiftListProvider);
    final user = ref.watch(sessionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Shifts', style: t.pageTitle)),
        const SizedBox(height: Space.x16),
        Expanded(
          child: switch (list) {
            AsyncError(:final error) => Align(
              alignment: Alignment.topLeft,
              child: Note.error(
                '$error',
                title: 'The shifts could not be loaded.',
              ),
            ),
            AsyncData(value: final shifts) when shifts.isEmpty => const Align(
              alignment: Alignment.topLeft,
              child: Note.info('No shifts yet.'),
            ),
            AsyncData(value: final shifts) => ListView.separated(
              key: const ValueKey('shifts.list'),
              itemCount: shifts.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.x8),
              itemBuilder: (context, i) => _ShiftCard(
                shifts[i],
                canClose:
                    user != null &&
                    shifts[i].isOpen &&
                    mayCloseShift(user, shiftUserId: shifts[i].userId),
              ),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard(this.shift, {required this.canClose});

  final ShiftSummary shift;
  final bool canClose;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final s = shift;
    final variance = s.variance;
    final high = variance != null && highVariance(variance, takings: s.takings);
    final recount = s.firstCount == null || s.counted == null
        ? null
        : recountLine(s.firstCount!, s.counted!);
    final closedBy = s.closedByName == null
        ? null
        : closedByLine(closer: s.closedByName!, owner: s.userName);

    return Container(
      key: ValueKey('shifts.item.${s.id}'),
      padding: const EdgeInsets.all(Space.x16),
      decoration: BoxDecoration(
        color: high ? c.butter : c.white,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: high ? c.butterBorder : c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(s.userName, style: t.bodyStrong),
                    const SizedBox(width: Space.x8),
                    if (s.isOpen)
                      const StatusBadge('OPEN', tone: BadgeTone.neutral),
                  ],
                ),
                Text(
                  s.isOpen
                      ? 'Since ${formatDayDateTime(s.openedAt)} · float '
                            '${formatKes(s.openingFloat)} · taken '
                            '${formatKes(s.takings)}'
                      : '${formatDayDateTime(s.openedAt)} → '
                            '${formatDayDateTime(s.closedAt!)} · taken '
                            '${formatKes(s.takings)}',
                  style: t.small.copyWith(color: high ? c.butterText : c.muted),
                ),
                if (!s.isOpen) ...[
                  const SizedBox(height: Space.x6),
                  Text(
                    'Expected ${formatKes(s.expectedCash!)} · counted '
                    '${formatKes(s.counted!)} · M-Pesa '
                    '${formatKes(s.expectedPaybill!)}',
                    style: t.small.copyWith(
                      color: high ? c.butterText : c.inkSoft,
                    ),
                  ),
                  if (recount != null)
                    Text(
                      recount,
                      key: ValueKey('shifts.recount.${s.id}'),
                      style: t.small.copyWith(
                        color: high ? c.butterText : c.inkSoft,
                      ),
                    ),
                  if (s.note != null)
                    Text(
                      '“${s.note}”',
                      style: t.small.copyWith(
                        color: high ? c.butterText : c.inkSoft,
                      ),
                    ),
                  if (closedBy != null)
                    Text(
                      closedBy,
                      key: ValueKey('shifts.closedBy.${s.id}'),
                      style: t.small.copyWith(
                        color: high ? c.butterText : c.muted,
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.x12),
          if (variance != null)
            Text(
              varianceLabel(variance),
              key: ValueKey('shifts.variance.${s.id}'),
              style: t.monoStrong.copyWith(color: high ? c.butterText : c.ink),
            )
          else if (canClose)
            AppButton.secondary(
              key: ValueKey('shifts.close.${s.id}'),
              label: 'Close this shift',
              compact: true,
              onPressed: () => context.go(Routes.closeShiftFor(s.id)),
            ),
        ],
      ),
    );
  }
}
