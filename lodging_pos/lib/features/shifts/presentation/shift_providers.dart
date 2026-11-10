import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/clock/clock.dart';
import '../data/drawer_repository.dart';
import '../data/shift_repository.dart';
import '../domain/drawer.dart';
import '../domain/shift.dart';
import '../domain/shift_close.dart';

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

  /// Opens [user]'s shift; the float is the drawer's (Story B).
  Future<void> open(UserAccount user) async {
    final shift = await ref.read(shiftRepositoryProvider).openShift(user: user);
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

/// Drawer checks and collections (Story B2). Kept alive: it remembers which
/// co-signs were used.
@Riverpod(keepAlive: true)
DrawerRepository drawerRepository(Ref ref) => DrawerRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
  ref.watch(passwordHasherProvider),
  ref.watch(clockProvider),
);

/// Whether the drawer has been counted at least once (the starting cash).
@riverpod
Future<bool> drawerStarted(Ref ref) =>
    ref.watch(shiftRepositoryProvider).drawerStarted();

/// Where [shiftId]'s close is (first count, recount, reason), from the shift
/// itself.
@riverpod
Future<CountStage> closeStage(Ref ref, String shiftId) =>
    ref.watch(shiftRepositoryProvider).countStageOf(shiftId);

/// What the drawer should hold now, for [viewShiftTotals] users only; null
/// for anyone else and before any count.
@riverpod
Future<int?> drawerNow(Ref ref) async {
  final user = ref.watch(sessionProvider);
  if (user == null || !can(user, Permission.viewShiftTotals)) return null;
  // Read again whenever the chain changes.
  ref.watch(drawerChainProvider);
  return ref.watch(shiftRepositoryProvider).drawerNow(user);
}

/// The drawer's chain, newest first, for [viewShiftTotals] users only.
@riverpod
Stream<List<ChainEntry>> drawerChain(Ref ref) {
  final user = ref.watch(sessionProvider);
  if (user == null || !can(user, Permission.viewShiftTotals)) {
    return Stream.value(const []);
  }
  return ref.watch(shiftRepositoryProvider).watchDrawerChain(user);
}

/// The supervisor's list of shifts (FD-11), watched.
@riverpod
Stream<List<ShiftSummary>> shiftList(Ref ref) =>
    ref.watch(shiftRepositoryProvider).watchShifts();

/// An open shift by id, for closing someone else's (FD-11).
@riverpod
Future<OpenShift?> openShiftById(Ref ref, String shiftId) =>
    ref.watch(shiftRepositoryProvider).openShiftById(shiftId);
