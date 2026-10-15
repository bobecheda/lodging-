import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/database/database_provider.dart';
import '../data/rooms_repository.dart';
import '../domain/bed_category.dart';
import '../domain/rooms.dart';

part 'rooms_providers.g.dart';

@Riverpod(keepAlive: true)
RoomsRepository roomsRepository(Ref ref) => RoomsRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
);

/// All rooms with their beds, naturally sorted. Call `ref.invalidate` after a
/// write to reload.
@riverpod
Future<List<RoomSummary>> roomsList(Ref ref) =>
    ref.watch(roomsRepositoryProvider).rooms();

/// Bed categories for the selects (active and inactive, in sort order).
@riverpod
Future<List<BedCategory>> bedCategories(Ref ref) =>
    ref.watch(roomsRepositoryProvider).categories();
