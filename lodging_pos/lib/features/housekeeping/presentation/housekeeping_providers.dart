import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/database/database_provider.dart';
import '../data/housekeeping_repository.dart';
import '../domain/housekeeping.dart';

part 'housekeeping_providers.g.dart';

@Riverpod(keepAlive: true)
HousekeepingRepository housekeepingRepository(Ref ref) =>
    HousekeepingRepository(
      ref.watch(appDatabaseProvider),
      ref.watch(auditWriterProvider),
    );

/// One bed for the cleaning panel, watched.
@riverpod
Stream<BedCleaning> bedCleaning(Ref ref, String bedId) =>
    ref.watch(housekeepingRepositoryProvider).watchBed(bedId);

/// Active housekeepers, for the dropdown.
@riverpod
Stream<List<HousekeeperOption>> activeHousekeepers(Ref ref) =>
    ref.watch(housekeepingRepositoryProvider).watchHousekeepers();
