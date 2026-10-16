import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/database/database_provider.dart';
import '../data/staff_repository.dart';
import '../domain/staff.dart';

part 'staff_providers.g.dart';

@Riverpod(keepAlive: true)
StaffRepository staffRepository(Ref ref) => StaffRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
  ref.watch(passwordHasherProvider),
);

/// Everyone who signs in. Invalidate after a write.
@riverpod
Future<List<UserSummary>> staffUsers(Ref ref) =>
    ref.watch(staffRepositoryProvider).users();

/// Housekeepers, active first. Invalidate after a write.
@riverpod
Future<List<Housekeeper>> housekeepersList(Ref ref) =>
    ref.watch(staffRepositoryProvider).housekeepers();
