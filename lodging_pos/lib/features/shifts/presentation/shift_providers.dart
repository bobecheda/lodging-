import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database_provider.dart';
import '../data/shift_repository.dart';
import '../domain/shift.dart';

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
  }
}
