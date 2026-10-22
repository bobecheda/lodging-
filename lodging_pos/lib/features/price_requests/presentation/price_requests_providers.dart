import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/clock/clock.dart';
import '../../../core/database/database_provider.dart';
import '../data/price_requests_repository.dart';

part 'price_requests_providers.g.dart';

@Riverpod(keepAlive: true)
PriceRequestsRepository priceRequestsRepository(Ref ref) =>
    PriceRequestsRepository(
      ref.watch(appDatabaseProvider),
      ref.watch(auditWriterProvider),
    );

/// Requests waiting for the owner, oldest first: the owner's Prices cards
/// and sidebar badge. Read again whenever a request, decision or price
/// changes.
@riverpod
Stream<List<PriceRequestView>> waitingPriceRequests(Ref ref) async* {
  final repo = ref.watch(priceRequestsRepositoryProvider);
  yield await repo.waiting();
  await for (final _ in repo.changes()) {
    yield await repo.waiting();
  }
}

/// The supervisor's Price requests card, read again on every change.
@riverpod
Stream<SupervisorPriceRequests> supervisorPriceRequests(Ref ref) async* {
  final repo = ref.watch(priceRequestsRepositoryProvider);
  final clock = ref.watch(clockProvider);
  yield await repo.forSupervisor(clock.now());
  await for (final _ in repo.changes()) {
    yield await repo.forSupervisor(clock.now());
  }
}
