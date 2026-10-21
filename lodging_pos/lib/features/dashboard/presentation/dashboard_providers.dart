import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/clock/clock.dart';
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
  });

  final List<MoneyMove> moves;
  final List<StayNights> stays;
  final List<RefundAwaiting> awaiting;
}

/// Read again whenever a payment, refund, void, stay or charge changes.
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
  );
}
