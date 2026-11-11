import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/clock.dart';
import '../../shifts/domain/cash_review.dart';
import '../../shifts/presentation/shift_providers.dart';
import '../../../core/database/database_provider.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard.dart';

part 'dashboard_providers.g.dart';

@Riverpod(keepAlive: true)
DashboardRepository dashboardRepository(Ref ref) =>
    DashboardRepository(ref.watch(appDatabaseProvider));

/// What Today's money, This month and Needs your attention are worked out
/// from, from the start of last month on.
final class TodayData {
  const TodayData({
    required this.moves,
    required this.stays,
    required this.awaiting,
    required this.prices,
    this.unpaid = const [],
    this.rejectedReviews = const [],
  });

  final List<MoneyMove> moves;
  final List<StayNights> stays;
  final List<RefundAwaiting> awaiting;

  /// Price requests waiting for the owner.
  final List<PriceAwaiting> prices;

  /// Guests in a bed whose payment was voided (AD-7).
  final List<UnpaidStay> unpaid;

  /// Cash reviews rejected in the last week (Story B3), newest first.
  final List<RejectedReview> rejectedReviews;
}

/// Read again whenever a payment, refund, void, stay, charge or price
/// request changes.
@riverpod
Future<TodayData> todayData(Ref ref) async {
  final repo = ref.watch(dashboardRepositoryProvider);
  final changes = repo.changes().listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
  final now = ref.watch(clockProvider).now();
  // Last month's start also covers the same weekday last week.
  final from = monthStart(sameMomentLastMonth(now));
  return TodayData(
    moves: await repo.moneyMoves(from),
    stays: await repo.stayNights(from),
    awaiting: await repo.refundsAwaiting(),
    prices: await repo.pricesAwaiting(),
    unpaid: unpaidStays(await repo.activeStayCharges()),
    rejectedReviews: switch (ref.watch(sessionProvider)) {
      final user? when can(user, Permission.viewShiftTotals) =>
        await ref
            .watch(cashReviewsRepositoryProvider)
            .rejectedSince(now.subtract(const Duration(days: 7)), by: user),
      _ => const [],
    },
  );
}
