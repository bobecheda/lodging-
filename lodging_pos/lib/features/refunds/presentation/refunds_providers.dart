import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/clock/clock.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/refunds_repository.dart';

part 'refunds_providers.g.dart';

@Riverpod(keepAlive: true)
RefundsRepository refundsRepository(Ref ref) => RefundsRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
  cloud: ref.watch(cloudWritesProvider),
);

/// The desk's Refunds lists, read again whenever a refund, decision or
/// payout changes.
@riverpod
Stream<DeskRefunds> deskRefunds(Ref ref) async* {
  final repo = ref.watch(refundsRepositoryProvider);
  final clock = ref.watch(clockProvider);
  yield await repo.deskRefunds(clock.now());
  await for (final _ in repo.changes()) {
    yield await repo.deskRefunds(clock.now());
  }
}

/// Approved refunds waiting to be paid: the Refunds sidebar badge.
@riverpod
Stream<int> refundsToPay(Ref ref) async* {
  final repo = ref.watch(refundsRepositoryProvider);
  final clock = ref.watch(clockProvider);
  yield (await repo.deskRefunds(clock.now())).toPay.length;
  await for (final _ in repo.changes()) {
    yield (await repo.deskRefunds(clock.now())).toPay.length;
  }
}

/// One refund for the owner's detail, read again when it changes.
@riverpod
Stream<RefundDetail> refundDetail(Ref ref, String refundId) async* {
  final repo = ref.watch(refundsRepositoryProvider);
  yield await repo.detail(refundId);
  await for (final _ in repo.changes()) {
    yield await repo.detail(refundId);
  }
}

/// One refund for the pay panel, read again when it changes.
@riverpod
Stream<RefundView> refundView(Ref ref, String refundId) async* {
  final repo = ref.watch(refundsRepositoryProvider);
  yield await repo.view(refundId);
  await for (final _ in repo.changes()) {
    yield await repo.view(refundId);
  }
}
