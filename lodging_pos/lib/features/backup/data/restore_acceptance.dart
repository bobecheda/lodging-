import 'dart:math' as math;

import '../../../core/app_version.dart';
import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/clock/clock.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/database/database.dart';
import '../../../core/database/desk_meta.dart';
import '../../../core/database/desk_startup.dart';
import '../../../core/sync/cloud.dart';

/// The owner's account in the restored file, read without opening it for
/// writing.
final class RestoreOwner {
  const RestoreOwner({
    required this.id,
    required this.passwordHash,
    required this.isActive,
  });

  final String id;
  final String passwordHash;
  final bool isActive;
}

/// The restore wasn't accepted; [message] says why.
class RestoreRefused implements Exception {
  const RestoreRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The desk has sent to the cloud, but this build has no cloud keys
/// (`secrets.json`), so the cloud can't be checked: the restore waits.
final class RestoreNeedsCloud extends RestoreRefused {
  const RestoreNeedsCloud()
    : super(
        'This desk sends its records to the cloud, so the cloud must be '
        'checked before an older backup is used, and this copy of the app '
        'can’t reach the cloud. Start the desk from its usual shortcut, or '
        'call support.',
      );
}

/// The restored file doesn't know the owner's cloud email: the screen asks
/// for it.
final class RestoreNeedsEmail extends RestoreRefused {
  const RestoreNeedsEmail()
    : super('Type the owner’s email, the one used on the phone.');
}

/// Accepting an older backup as the live database, after the "older than
/// the last backup" refusal (docs/backup-restore.md, "Restoring an older
/// backup"): the owner only, with their password, and the number on the
/// last receipt printed. On a desk that has synced, the cloud is checked
/// first with the owner's sign-in (story/restore-cloud-check): anything
/// from this desk newer than the backup refuses the restore. Nothing in
/// the database changes here: the mark is reset to the restored file with
/// the restore pending, and [applyPendingRestore] finishes it once the
/// file opens.
class RestoreAcceptance {
  RestoreAcceptance({
    required this.readOwner,
    required this.hasher,
    required this.deskConnected,
    required this.writeMark,
    required this.clock,
    this.cloud,
  });

  final Future<RestoreOwner?> Function() readOwner;
  final PasswordHasher hasher;

  /// Whether this desk still has its cloud key.
  final Future<bool> Function() deskConnected;
  final Future<void> Function(HighWaterMark mark) writeMark;
  final Clock clock;

  /// The cloud; null in a build without cloud keys.
  final Cloud? cloud;

  Future<void> accept(
    OlderThanBackup refused, {
    required String password,
    required String lastPaperReceipt,
    String? ownerEmail,
  }) async {
    final live = refused.live;
    final synced = live.everConnected || await deskConnected();
    final owner = await readOwner();
    if (owner == null || !owner.isActive) {
      throw const RestoreRefused('This file has no owner’s account.');
    }
    final paper = receiptSerial(lastPaperReceipt.trim());
    DeskInCloud? inCloud;
    if (synced) {
      inCloud = await _checkCloud(
        live,
        password: password,
        email: (ownerEmail ?? '').trim().isNotEmpty
            ? ownerEmail!.trim()
            : live.ownerEmail,
      );
    } else if (!await hasher.verify(password, owner.passwordHash)) {
      throw const RestoreRefused('That isn’t the owner’s password.');
    }
    if (lastPaperReceipt.trim().isEmpty || paper == 0) {
      throw const RestoreRefused(
        'Type the number on the last receipt printed, e.g. R-000061.',
      );
    }
    final now = clock.now();
    final floor = [
      live.nextReceiptNumber,
      receiptSerial(live.figures.lastReceipt) + 1,
      receiptSerial(refused.mark.figures.lastReceipt) + 1,
      receiptSerial(inCloud?.lastReceipt) + 1,
      paper + 1,
    ].reduce(math.max);
    await writeMark(
      HighWaterMark(
        backupName: 'restore accepted',
        takenAt: now,
        figures: refused.live.figures,
        build: AppBuild.current.stamp,
        pendingRestore: PendingRestore(
          acceptedBy: owner.id,
          acceptedAt: now,
          counterFloor: floor,
          previous: refused.mark.figures,
          cloudChecked: inCloud != null,
        ),
      ),
    );
  }

  /// Signs in as the owner (the password is checked by the cloud, where a
  /// change made on the phone lives), reads what the cloud holds from this
  /// desk, signs out again. Refuses if anything there is newer than the
  /// restored file's last audit entry: restoring would lose those records
  /// and jam the push (docs/backup-restore.md).
  Future<DeskInCloud> _checkCloud(
    LiveFile live, {
    required String password,
    required String? email,
  }) async {
    final cloud = this.cloud;
    final deviceId = live.deviceId;
    if (cloud == null || deviceId == null) throw const RestoreNeedsCloud();
    if (email == null || email.isEmpty) throw const RestoreNeedsEmail();
    final DeskInCloud inCloud;
    try {
      await cloud.signInOwner(email, password);
      inCloud = await cloud.deskInCloud(deviceId);
    } on CloudSignInRefused {
      throw const RestoreRefused('That isn’t the owner’s email and password.');
    } on CloudOffline {
      throw const RestoreRefused(
        'The cloud must be checked first, and it can’t be reached. Connect '
        'the internet and try again.',
      );
    } on CloudRefused catch (e) {
      throw RestoreRefused(e.message);
    } finally {
      await cloud.signOutOwner();
    }
    final cloudLast = inCloud.lastAuditAt;
    final fileLast = live.figures.lastAuditAt;
    if (cloudLast != null &&
        (fileLast == null || cloudLast.isAfter(fileLast))) {
      throw RestoreRefused(
        'The cloud has newer records from this desk (last at '
        '${formatDayDateTime(cloudLast)}; this backup ends at '
        '${fileLast == null ? 'nothing' : formatDayDateTime(fileLast)}). '
        'Using this backup would lose them and reuse receipt numbers. '
        'Don’t use it: call support.',
      );
    }
    return inCloud;
  }
}

/// Finishes an accepted restore once the database is open, before anyone
/// signs in: the receipt counter moves up to the floor and
/// `database.restore_accepted` is audited (the counter isn't audited or
/// synced itself), then the mark loses its pending part.
Future<void> applyPendingRestore(
  AppDatabase db,
  AuditWriter audit,
  HighWaterMark mark, {
  required Future<void> Function(HighWaterMark mark) writeMark,
}) async {
  final pending = mark.pendingRestore;
  if (pending == null) return;
  await db.transaction(() async {
    final (before, after) = await raiseReceiptCounter(db, pending.counterFloor);
    await audit.recordEvent(
      action: 'database.restore_accepted',
      userId: pending.acceptedBy,
      entity: 'database',
      entityId: await db.deviceId(),
      details: {
        'restored': mark.figures.describe(),
        'last_backup': pending.previous.describe(),
        'counter_before': before,
        'counter_after': after,
        'cloud_checked': pending.cloudChecked,
      },
    );
  });
  await writeMark(mark.withoutPending());
}
