import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/clock.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/database/schema_check.dart';
import '../../../core/settings/settings_repository.dart';
import '../data/backup_files.dart' as files;
import '../data/backup_service.dart';
import '../domain/backup.dart';

part 'backup_providers.g.dart';

/// Where the main backups go, or null where the desk takes none: web, the
/// admin phone, and tests unless they set a folder.
@Riverpod(keepAlive: true)
Future<String> Function()? backupFolder(Ref ref) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
    ? files.defaultBackupFolder
    : null;

/// How often a running desk checks that today has a backup. Null in tests,
/// which call [Backups.checkNow] themselves.
@Riverpod(keepAlive: true)
Duration? backupCheckInterval(Ref ref) => const Duration(hours: 1);

/// The folder picker and Explorer. Tests replace them.
abstract interface class BackupShell {
  /// The chosen folder, or null if cancelled.
  Future<String?> pickFolder();

  Future<void> openFolder(String path);
}

final class DeviceBackupShell implements BackupShell {
  const DeviceBackupShell();

  @override
  Future<String?> pickFolder() => files.pickFolder();

  @override
  Future<void> openFolder(String path) => files.openFolder(path);
}

@Riverpod(keepAlive: true)
BackupShell backupShell(Ref ref) => const DeviceBackupShell();

/// What the Backups card and the sidebar show.
final class BackupStatus {
  const BackupStatus({
    this.enabled = false,
    this.folder,
    this.newest,
    this.lastFailure,
    this.secondFolder,
    this.second,
    this.running = false,
  });

  /// Backups run on this device (the Windows desk).
  final bool enabled;

  /// The main folder, once known.
  final String? folder;
  final BackupFile? newest;

  /// Why the last main backup failed; null once one succeeds.
  final String? lastFailure;
  final String? secondFolder;

  /// What happened to the last backup's second copy; null if none was due.
  final SecondCopy? second;
  final bool running;

  /// The sidebar's warning ([backupOverdue]).
  bool overdueAt(DateTime now) =>
      enabled &&
      backupOverdue(
        newest: newest?.takenAt,
        lastFailed: lastFailure != null,
        now: now,
      );

  BackupStatus copyWith({
    String? folder,
    BackupFile? newest,
    Object? lastFailure = _keep,
    Object? secondFolder = _keep,
    Object? second = _keep,
    bool? running,
  }) => BackupStatus(
    enabled: enabled,
    folder: folder ?? this.folder,
    newest: newest ?? this.newest,
    lastFailure: lastFailure == _keep
        ? this.lastFailure
        : lastFailure as String?,
    secondFolder: secondFolder == _keep
        ? this.secondFolder
        : secondFolder as String?,
    second: second == _keep ? this.second : second as SecondCopy?,
    running: running ?? this.running,
  );
}

const _keep = Object();

/// The daily local backup: once the database check has passed at start,
/// then every [backupCheckInterval], it backs up if today (Nairobi) has no
/// backup yet; also after every shift close and on "Back up now". One
/// backup at a time: a request made while one runs waits, then takes its
/// own, so a shift closed mid-backup is still in a copy. It never blocks
/// the desk.
@Riverpod(keepAlive: true)
class Backups extends _$Backups {
  BackupService? _service;

  /// The requests in order; each starts when the one before has finished.
  Future<void> _queue = Future.value();

  /// A daily check waiting for its turn.
  Future<void>? _check;
  Timer? _timer;
  var _started = false;

  @override
  BackupStatus build() {
    final folder = ref.watch(backupFolderProvider);
    if (folder == null) return const BackupStatus();
    final interval = ref.watch(backupCheckIntervalProvider);
    ref.onDispose(() => _timer?.cancel());
    // Only once the database check has passed (a mismatched file is never
    // backed up as if it were good).
    ref.listen(schemaDriftProvider, (_, next) {
      if (_started || next is! AsyncData<SchemaDrift?> || next.value != null) {
        return;
      }
      _started = true;
      // After build returns: checkNow reads and sets the state.
      unawaited(_quietly(Future.microtask(checkNow)));
      if (interval != null) {
        _timer = Timer.periodic(
          interval,
          (_) => unawaited(_quietly(checkNow())),
        );
      }
    }, fireImmediately: true);
    return const BackupStatus(enabled: true);
  }

  Future<BackupService> _backups() async {
    final existing = _service;
    if (existing != null) return existing;
    final folder = await ref.read(backupFolderProvider)!();
    return _service = BackupService(
      ref.read(appDatabaseProvider),
      ref.read(auditWriterProvider),
      ref.read(clockProvider),
      ref.read(settingsRepositoryProvider),
      folder: folder,
    );
  }

  /// Reads the folders, and backs up if today has no backup yet. A check
  /// still waiting its turn answers for the next one too, so checks never
  /// pile up behind a slow backup.
  Future<void> checkNow() {
    if (!state.enabled) return Future.value();
    return _check ??= _inTurn(() async {
      _check = null;
      final service = await _backups();
      final newest = await service.newest();
      state = state.copyWith(
        folder: service.folder,
        newest: newest,
        secondFolder: await service.secondFolder(),
      );
      if (isBackupDue(
        newest: newest?.takenAt,
        now: ref.read(clockProvider).now(),
      )) {
        await _take(BackupReason.daily, null);
      }
    });
  }

  /// "Back up now" ([Permission.manageBackups]). Throws [BackupFailed]; the
  /// card shows it.
  Future<BackupDone> backUpNow(UserAccount user) {
    requirePermission(user, Permission.manageBackups);
    return _inTurn(() => _take(BackupReason.manual, user));
  }

  /// Right after [user] closed a shift. Runs in the background.
  void afterShiftClose(UserAccount user) {
    if (!state.enabled) return;
    unawaited(_quietly(_inTurn(() => _take(BackupReason.shiftClose, user))));
  }

  /// Sets or clears (null) the second folder. The next backup uses it.
  Future<void> setSecondFolder(UserAccount user, String? path) async {
    requirePermission(user, Permission.manageBackups);
    final service = await _backups();
    await service.setSecondFolder(user, path);
    final value = path?.trim();
    state = state.copyWith(
      secondFolder: value == null || value.isEmpty ? null : value,
      second: null,
    );
  }

  Future<T> _inTurn<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<BackupDone> _take(BackupReason reason, UserAccount? by) async {
    final service = await _backups();
    state = state.copyWith(folder: service.folder, running: true);
    try {
      final done = await service.backUp(reason: reason, by: by);
      state = state.copyWith(
        newest: done.file,
        lastFailure: null,
        second: done.second,
        running: false,
      );
      return done;
    } on BackupFailed catch (e) {
      state = state.copyWith(lastFailure: e.message, running: false);
      rethrow;
    } catch (_) {
      state = state.copyWith(running: false);
      rethrow;
    }
  }

  /// Background runs report through [state]; nothing to throw to.
  Future<void> _quietly(Future<void> work) => work.catchError((Object _) {});
}
