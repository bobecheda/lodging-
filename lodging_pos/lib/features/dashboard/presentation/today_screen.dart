import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/notes.dart';
import '../../bed_board/domain/bed_board.dart';
import '../../bed_board/presentation/bed_board_providers.dart';
import '../domain/dashboard.dart';
import 'dashboard_providers.dart';
import 'today_cards.dart';

/// The owner's Today on the desk (`viewBusinessDashboard`), matching the
/// phone design (Figma "01 Today"): Needs your attention, Today's money,
/// Beds right now and This month. Read-only; the figures come from
/// `domain/dashboard.dart`.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LodgingType.of(context);
    final c = LodgingColors.of(context);
    final now = ref.watch(boardNowProvider).value;
    final data = ref.watch(todayDataProvider);
    final rooms = ref.watch(boardRoomsProvider);
    final grace = ref.watch(boardGraceMinutesProvider).value;

    final Widget body;
    if (data.error ?? rooms.error case final error?) {
      body = Note.error('$error', title: 'Today could not be loaded.');
    } else if (now == null ||
        grace == null ||
        data.value == null ||
        rooms.value == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final d = data.value!;
      final beds = BedsNow.fromCounts(
        boardView(
          rooms.value!,
          const BoardFilter(),
          now: now,
          graceMinutes: grace,
        ).counts,
      );
      final money = todaysMoney(d.moves, now);
      final month = thisMonth(
        moves: d.moves,
        stays: d.stays,
        activeBeds: beds.total,
        now: now,
      );
      Widget row(Widget a, Widget b) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: a),
            const SizedBox(width: Space.x20),
            Expanded(child: b),
          ],
        ),
      );
      body = SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              AttentionCard(
                rows: [
                  for (final r in d.awaiting)
                    AttentionRow.refund(
                      r,
                      onTap: () =>
                          context.go(Routes.refundDetailFor(r.refundId)),
                    ),
                  for (final p in d.prices)
                    AttentionRow.price(
                      p,
                      now: now,
                      onTap: () => context.go(Routes.adminPrices),
                    ),
                ],
              ),
              MoneyCard(money, vsLine: vsLastWeekLine(money, now)),
            ),
            const SizedBox(height: Space.x20),
            row(BedsCard(beds), MonthCard(month, now: now)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Today', style: t.pageTitle)),
        if (now != null)
          Text(
            formatLongDate(now),
            key: const ValueKey('today.date'),
            style: t.small.copyWith(color: c.muted),
          ),
        const SizedBox(height: Space.x20),
        Expanded(child: body),
      ],
    );
  }
}
