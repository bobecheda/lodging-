import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/database/database_provider.dart';
import '../data/login_service.dart';
import '../data/user_repository.dart';
import '../domain/setup.dart';

part 'auth_providers.g.dart';

@Riverpod(keepAlive: true)
UserRepository userRepository(Ref ref) => UserRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
  ref.watch(passwordHasherProvider),
);

@Riverpod(keepAlive: true)
LoginService loginService(Ref ref) => LoginService(
  ref.watch(userRepositoryProvider),
  ref.watch(passwordHasherProvider),
  ref.watch(auditWriterProvider),
);

/// Where first-run setup stands ([SetupState]). Until it is ready, only the
/// setup screen is reachable; once ready, it is unreachable.
@Riverpod(keepAlive: true)
class SetupStatus extends _$SetupStatus {
  @override
  Future<SetupState> build() => ref.watch(userRepositoryProvider).setupState();

  void markDone() => state = const AsyncData(SetupState.ready);
}
