import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/app_version.dart';
import '../../core/audit/audit_writer.dart';
import '../../core/auth/password_hasher.dart';
import '../../core/clock/clock.dart';
import '../../core/database/database_files.dart';
import '../../core/database/database_provider.dart';
import '../../core/database/desk_meta.dart';
import '../../core/database/desk_startup.dart';
import '../../core/database/desk_startup_provider.dart';
import '../../core/database/mark_keeper.dart';
import '../../core/database/schema_check.dart';
import '../../core/sync/sync_providers.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/backup/data/restore_acceptance.dart';
import 'unusual_start.dart';

part 'startup_providers.g.dart';

/// Once the database check passes, on the real desk only (story/desk-db-
/// guards): finish an accepted restore, raise the file's build stamp, and
/// record the install folder on the first run. Since story/desk-db-guards-2
/// the marks move with the work from here on, and a missing copy is written
/// again. Sign-in waits for it.
@Riverpod(keepAlive: true)
Future<void> startupTasks(Ref ref) async {
  final drift = await ref.watch(schemaDriftProvider.future);
  final startup = ref.watch(deskStartupProvider);
  if (drift != null || startup.folder == null) return;
  final db = ref.watch(appDatabaseProvider);
  final marks = ref.watch(markStoreProvider);
  if (startup.inspection.mark case final mark?
      when mark.pendingRestore != null && marks != null) {
    await applyPendingRestore(
      db,
      ref.read(auditWriterProvider),
      mark,
      marks: marks,
    );
  }
  await raiseBuildStamp(db, AppBuild.current);
  if (marks != null) {
    final clock = ref.read(clockProvider);
    ref.read(auditWriterProvider).onCommitted = MarkKeeper(
      db,
      marks,
      clock,
    ).afterCommit;
    await marks.raise(await liveFigures(db), at: clock.now());
  }
  if (startup.location case LocationRecord(:final path)) {
    await recordInstallPath(db, path);
  }
}

/// The longest sign-in waits for the cloud's answer at start.
const cloudCheckWait = Duration(seconds: 8);

/// Before sign-in, on a connected desk that is online
/// (story/desk-db-guards-2): asks the cloud whether this file is behind it
/// (`SyncEngine.checkCloud`). Offline, refused or slower than
/// [cloudCheckWait], the desk opens as today; the engine asks again before
/// it sends anything.
@Riverpod(keepAlive: true)
Future<void> cloudStartupCheck(Ref ref) async {
  await ref.watch(startupTasksProvider.future);
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return;
  try {
    await engine.ready.then((_) => engine.checkCloud()).timeout(cloudCheckWait);
  } on TimeoutException {
    // Opens as today.
  }
}

/// Accepting an older backup from the refusal screen, before the database
/// opens: the owner's account is read from the file read-only.
@Riverpod(keepAlive: true)
RestoreAcceptance restoreAcceptance(Ref ref) {
  final folder = ref.watch(deskStartupProvider).folder;
  return RestoreAcceptance(
    readOwner: () async =>
        switch (folder == null ? null : readOwnerFromFile(folder)) {
          final o? => RestoreOwner(
            id: o.id,
            passwordHash: o.passwordHash,
            isActive: o.isActive,
          ),
          null => null,
        },
    hasher: ref.watch(passwordHasherProvider),
    deskConnected: () async =>
        await ref.read(deskSecretStoreProvider).read() != null,
    marks: ref.watch(markStoreProvider) ?? const NoMarks(),
    clock: ref.watch(clockProvider),
    cloud: ref.watch(cloudProvider),
  );
}

/// The unusual start still to be accepted, or null (story/desk-db-guards).
@Riverpod(keepAlive: true)
class UnusualStart extends _$UnusualStart {
  @override
  UnusualLocation? build() => switch (ref.watch(deskStartupProvider).location) {
    final UnusualLocation location => location,
    _ => null,
  };

  /// The supervisor or owner carries on; throws [UnusualStartRefused].
  Future<void> accept({
    required String username,
    required String password,
    required bool makeInstallFolder,
  }) async {
    final location = state;
    if (location == null) return;
    await UnusualStartService(
      ref.read(appDatabaseProvider),
      ref.read(auditWriterProvider),
      ref.read(userRepositoryProvider),
      ref.read(passwordHasherProvider),
    ).accept(
      location,
      username: username,
      password: password,
      makeInstallFolder: makeInstallFolder,
    );
    state = null;
  }
}
