import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/clock.dart';
import '../../../core/database/database.dart';
import '../../../core/settings/setting_defaults.dart';
import '../../../core/settings/settings_repository.dart';
import '../domain/backup.dart';
import 'backup_files.dart';

/// Why a backup was taken, as recorded in its audit entry.
enum BackupReason {
  /// The first chance on a new Nairobi day (at start, or the hourly check).
  daily('daily'),

  /// Right after a shift was closed, so the day's takings are in a copy.
  shiftClose('shift_close'),

  /// "Back up now" on the Backups card.
  manual('manual');

  const BackupReason(this.code);
  final String code;
}

/// A checked backup in the main folder.
final class BackupFile {
  const BackupFile({
    required this.name,
    required this.takenAt,
    required this.sizeBytes,
  });

  final String name;

  /// UTC.
  final DateTime takenAt;
  final int sizeBytes;
}

/// What happened to the copy in the optional second folder.
sealed class SecondCopy {
  const SecondCopy(this.folder);
  final String folder;
}

final class SecondCopied extends SecondCopy {
  const SecondCopied(super.folder);
}

/// The folder wasn't there (the USB drive unplugged). The main backup still
/// counts.
final class SecondSkipped extends SecondCopy {
  const SecondSkipped(super.folder);
}

final class SecondFailed extends SecondCopy {
  const SecondFailed(super.folder, this.message);
  final String message;
}

final class BackupDone {
  const BackupDone(this.file, this.second);
  final BackupFile file;

  /// Null when no second folder is set.
  final SecondCopy? second;
}

/// The main backup could not be made or failed its check. Nothing replaced
/// an earlier good backup.
final class BackupFailed implements Exception {
  const BackupFailed(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Makes the daily local backups (docs/backup-restore.md): a consistent
/// copy of the open database with `VACUUM INTO`, checked before it counts,
/// into the main folder and, if set, a second one; old ones pruned. Each
/// backup is audited (`backup.create` / `backup.failed`); no business rows
/// change.
class BackupService {
  BackupService(
    this._db,
    this._audit,
    this._clock,
    this._settings, {
    required this.folder,
  });

  final AppDatabase _db;
  final AuditWriter _audit;
  final Clock _clock;
  final SettingsRepository _settings;

  /// The main backup folder.
  final String folder;

  /// The newest backup in the main folder, or null if there is none.
  Future<BackupFile?> newest() async {
    final found = newestBackup(await fileNames(folder));
    if (found == null) return null;
    return BackupFile(
      name: found.name,
      takenAt: found.takenAt,
      sizeBytes: await fileSize(joinPath(folder, found.name)),
    );
  }

  /// The second folder, or null if none is set.
  Future<String?> secondFolder() async {
    final value = (await _settings.value(SettingKeys.backupSecondFolder))
        .trim();
    return value.isEmpty ? null : value;
  }

  /// Sets the second folder to [path], or clears it (null). Audited as
  /// `settings.update`.
  Future<void> setSecondFolder(UserAccount user, String? path) async {
    requirePermission(user, Permission.manageBackups);
    final value = path?.trim() ?? '';
    final key = SettingKeys.backupSecondFolder;
    final stored = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    if ((stored?.value ?? '') == value) return;
    await _audit.writeWithAudit(
      action: 'settings.update',
      userId: user.id,
      body: (w) async {
        if (stored != null) {
          await w.update(
            _db.settings,
            key,
            SettingsCompanion(value: Value(value), updatedBy: Value(user.id)),
          );
        } else {
          await w.insert(
            _db.settings,
            SettingsCompanion.insert(
              key: key,
              value: value,
              updatedBy: Value(user.id),
            ),
          );
        }
      },
    );
  }

  /// Takes a backup now. [by] is the signed-in user, if any; a manual one
  /// needs [Permission.manageBackups]. Throws [BackupFailed] if the main
  /// backup could not be made; a problem with the second copy is only
  /// reported in the result.
  Future<BackupDone> backUp({
    required BackupReason reason,
    UserAccount? by,
  }) async {
    if (reason == BackupReason.manual) {
      if (by == null) throw const NotPermitted(Permission.manageBackups);
      requirePermission(by, Permission.manageBackups);
    }
    final now = _clock.now();
    final name = backupFileName(now);
    final path = joinPath(folder, name);
    final partial = '$path.partial';

    final int size;
    try {
      await createFolder(folder);
      await deleteIfExists(partial);
      // A consistent copy of the open database, WAL included.
      await _db.customStatement('VACUUM INTO ?', [partial]);
      await _check(partial);
      await moveReplacing(partial, path);
      size = await fileSize(path);
    } catch (e) {
      final message = e is BackupFailed ? e.message : describeFileError(e);
      try {
        await deleteIfExists(partial);
      } catch (_) {
        // The folder itself is unreachable; nothing was left there.
      }
      await _recordFailure(reason, by, name, message);
      throw BackupFailed(message);
    }
    await _prune(folder, now);

    final second = await _copyToSecond(path, name, now);
    final file = BackupFile(name: name, takenAt: now, sizeBytes: size);
    await _audit.recordEvent(
      action: 'backup.create',
      userId: by?.id,
      entity: 'backups',
      entityId: name,
      details: {
        'file': name,
        'size': size,
        'reason': reason.code,
        'second_copy': switch (second) {
          null => 'none',
          SecondCopied() => 'copied',
          SecondSkipped() => 'skipped',
          SecondFailed() => 'failed',
        },
      },
    );
    return BackupDone(file, second);
  }

  /// The copy at [path] must pass SQLite's integrity check and carry this
  /// build's schema version before it may replace anything.
  Future<void> _check(String path) async {
    await _db.customStatement('ATTACH DATABASE ? AS backup_check', [path]);
    try {
      final integrity = await _db
          .customSelect('PRAGMA backup_check.integrity_check')
          .get();
      final result = [for (final r in integrity) '${r.data.values.first}'];
      if (result.length != 1 || result.single != 'ok') {
        throw BackupFailed(
          'The copy failed its check: ${result.take(3).join('; ')}',
        );
      }
      final version = await _db
          .customSelect('PRAGMA backup_check.user_version')
          .getSingle();
      if (version.data.values.first != _db.schemaVersion) {
        throw BackupFailed(
          'The copy has schema version ${version.data.values.first}, '
          'not ${_db.schemaVersion}.',
        );
      }
    } finally {
      await _db.customStatement('DETACH DATABASE backup_check');
    }
  }

  Future<void> _prune(String inFolder, DateTime now) async {
    for (final name in staleBackups(await fileNames(inFolder), now)) {
      await deleteIfExists(joinPath(inFolder, name));
    }
  }

  Future<SecondCopy?> _copyToSecond(
    String path,
    String name,
    DateTime now,
  ) async {
    final second = await secondFolder();
    if (second == null) return null;
    if (!await folderExists(second)) return SecondSkipped(second);
    final target = joinPath(second, name);
    final partial = '$target.partial';
    try {
      await deleteIfExists(partial);
      await copyFile(path, partial);
      if (await fileSize(partial) != await fileSize(path)) {
        throw const BackupFailed('The copy is incomplete.');
      }
      await moveReplacing(partial, target);
      await _prune(second, now);
      return SecondCopied(second);
    } catch (e) {
      try {
        await deleteIfExists(partial);
      } catch (_) {
        // The drive went away mid-copy.
      }
      return SecondFailed(
        second,
        e is BackupFailed ? e.message : describeFileError(e),
      );
    }
  }

  Future<void> _recordFailure(
    BackupReason reason,
    UserAccount? by,
    String name,
    String message,
  ) async {
    try {
      await _audit.recordEvent(
        action: 'backup.failed',
        userId: by?.id,
        entity: 'backups',
        entityId: name,
        details: {'reason': reason.code, 'error': message},
      );
    } catch (_) {
      // The database can't take it either (e.g. the disk is full); the
      // Backups card and the sidebar still show the failure.
    }
  }
}
