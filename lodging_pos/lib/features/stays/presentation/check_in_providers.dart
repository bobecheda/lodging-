import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/clock/clock_time.dart';
import '../../../core/database/database_provider.dart';
import '../../guests/domain/guest.dart';
import '../../guests/presentation/guests_providers.dart';
import '../../setup/domain/rooms.dart';
import '../data/check_in_repository.dart';

part 'check_in_providers.g.dart';

@Riverpod(keepAlive: true)
CheckInRepository checkInRepository(Ref ref) => CheckInRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
  ref.watch(guestsRepositoryProvider),
);

/// Open rooms with every bed, watched: the bed choices and Bed B's reason.
@riverpod
Stream<List<RoomSummary>> checkInRooms(Ref ref) =>
    ref.watch(checkInRepositoryProvider).watchRooms();

/// The checkout time setting, watched, for the dates shown.
@riverpod
Stream<ClockTime> checkInCheckoutTime(Ref ref) =>
    ref.watch(checkInRepositoryProvider).watchCheckoutTime();

/// A returning guest's earlier check-ins, for their card.
@riverpod
Future<GuestHistory> guestHistory(Ref ref, String guestId) =>
    ref.watch(checkInRepositoryProvider).guestHistory(guestId);
