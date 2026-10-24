import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/clock/clock.dart';
import '../../bed_board/domain/bed_board.dart';
import '../../dashboard/domain/dashboard.dart';
import '../../dashboard/presentation/today_cards.dart';
import '../data/owner_cloud.dart';
import 'owner_app.dart';
import 'owner_providers.dart';

/// The owner's Today on the phone (Figma "01 Today"): the desk's cards,
/// stacked, with shortages and voided payments under Needs your attention.
/// Pull down to reload.
class OwnerTodayScreen extends ConsumerWidget {
  const OwnerTodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(ownerTodayDataProvider);
    final now = ref.watch(clockProvider).now();
    Future<void> reload() =>
        ref.read(ownerTodayDataProvider.notifier).refresh();

    final snapshot = data.value;
    if (snapshot == null) {
      if (data.hasError) {
        final offline = data.error is OwnerCloudOffline;
        return ListView(
          padding: const EdgeInsets.all(Space.x16),
          children: [
            Note.error(
              offline
                  ? 'No internet connection. Today shows once the phone is '
                        'online.'
                  : '${data.error}',
              key: const ValueKey('owner.today.problem'),
              title: 'Today could not be loaded.',
            ),
            const SizedBox(height: Space.x12),
            AppButton.secondary(
              key: const ValueKey('owner.today.retry'),
              label: 'Try again',
              onPressed: reload,
            ),
          ],
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final d = snapshot.today;
    final beds = BedsNow.fromCounts(
      boardView(
        d.rooms,
        const BoardFilter(),
        now: now,
        graceMinutes: d.graceMinutes,
      ).counts,
    );
    final money = todaysMoney(d.moves, now);
    final month = thisMonth(
      moves: d.moves,
      stays: d.stays,
      activeBeds: beds.total,
      now: now,
    );
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        key: const ValueKey('owner.today'),
        padding: const EdgeInsets.all(Space.x16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AttentionCard(
            rows: [
              for (final r in d.refunds)
                AttentionRow.refund(
                  r,
                  onTap: () => context.go(OwnerRoutes.refundFor(r.refundId)),
                ),
              // Decided on Prices, in the next update.
              for (final p in d.prices) AttentionRow.price(p, now: now),
              for (final s in d.shortages)
                AttentionRow(
                  key: ValueKey('today.attention.short.${s.shiftId}'),
                  kind: AttentionKind.shortage,
                  title: s.title,
                  subtitle: s.subtitle(now),
                  figure: s.figure,
                ),
              for (final v in d.voids)
                AttentionRow(
                  key: ValueKey('today.attention.void.${v.voidId}'),
                  kind: AttentionKind.voided,
                  title: v.title,
                  subtitle: v.subtitle(now),
                  figure: v.figure,
                ),
            ],
          ),
          const SizedBox(height: Space.x16),
          MoneyCard(money, vsLine: vsLastWeekLine(money, now)),
          const SizedBox(height: Space.x16),
          BedsCard(beds),
          const SizedBox(height: Space.x16),
          MonthCard(month, now: now),
        ],
      ),
    );
  }
}
