import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database_provider.dart';
import '../data/shift_repository.dart';
import '../domain/shift.dart';
import '../domain/shift_rules.dart';

part 'shift_providers.g.dart';

@Riverpod(keepAlive: true)
ShiftRepository shiftRepository(Ref ref) => ShiftRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
);

/// The open shift on this device, if any.
@Riverpod(keepAlive: true)
class CurrentShift extends _$CurrentShift {
  @override
  Future<OpenShift?> build() =>
      ref.watch(shiftRepositoryProvider).openShiftOnThisDevice();

  Future<void> open(UserAccount user, int openingFloat) async {
    final shift = await ref
        .read(shiftRepositoryProvider)
        .openShift(user: user, openingFloat: openingFloat);
    state = AsyncData(shift);
    // A shift you just opened needs no "Continue my shift" step.
    ref.read(shiftContinuedProvider.notifier).confirm();
  }
}

/// Whether the signed-in receptionist has continued (or opened) their shift
/// in this sign-in. Resets on every sign-in, so returning to an open shift
/// always shows the resume card first.
@Riverpod(keepAlive: true)
class ShiftContinued extends _$ShiftContinued {
  @override
  bool build() {
    ref.listen(sessionProvider, (previous, next) {
      if (previous?.id != next?.id) state = false;
    });
    return false;
  }

  void confirm() => state = true;
}

/// Taken so far on [shiftId], for the resume card.
@riverpod
Future<ShiftTakings> shiftTakings(Ref ref, String shiftId) =>
    ref.watch(shiftRepositoryProvider).takings(shiftId);

/// The owner's list of shifts (FD-11), watched.
@riverpod
Stream<List<ShiftSummary>> shiftList(Ref ref) =>
    ref.watch(shiftRepositoryProvider).watchShifts();

/// An open shift by id, for closing someone else's (FD-11).
@riverpod
Future<OpenShift?> openShiftById(Ref ref, String shiftId) =>
    ref.watch(shiftRepositoryProvider).openShiftById(shiftId);
