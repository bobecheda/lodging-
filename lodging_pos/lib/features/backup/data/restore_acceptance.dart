import 'dart:math' as math;

import '../../../core/app_version.dart';
import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/clock/clock.dart';
import '../../../core/database/database.dart';
import '../../../core/database/desk_meta.dart';
import '../../../core/database/desk_startup.dart';

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

/// The desk has sent to the cloud: a restore waits for the cloud check
/// (story/restore-cloud-check), so new receipts can never reuse a number
/// the cloud already has (docs/backup-restore.md).
final class RestoreNeedsCloud extends RestoreRefused {
  const RestoreNeedsCloud()
    : super(
        'This desk sends its records to the cloud, so the cloud must be '
        'checked before an older backup is used. That check isn’t built '
        'yet: don’t use this desk, and call support.',
      );
}

/// Accepting an older backup as the live database, after the "older than
/// the last backup" refusal (docs/backup-restore.md, "Restoring an older
/// backup"): the owner only, with their password, and the number on the
/// last receipt printed. Nothing in the database changes here: the mark
/// is reset to the restored file with the restore pending, and
/// [applyPendingRestore] finishes it once the file opens.
class RestoreAcceptance {
  RestoreAcceptance({
    required this.readOwner,
    required this.hasher,
    required this.deskConnected,
    required this.writeMark,
    required this.clock,
  });

  final Future<RestoreOwner?> Function() readOwner;
  final PasswordHasher hasher;

  /// Whether this desk still has its cloud key.
  final Future<bool> Function() deskConnected;
  final Future<void> Function(HighWaterMark mark) writeMark;
  final Clock clock;

  Future<void> accept(
    OlderThanBackup refused, {
    required String password,
    required String lastPaperReceipt,
  }) async {
    if (refused.live.everConnected || await deskConnected()) {
      throw const RestoreNeedsCloud();
    }
    final owner = await readOwner();
    if (owner == null ||
        !owner.isActive ||
        !await hasher.verify(password, owner.passwordHash)) {
      throw const RestoreRefused('That isn’t the owner’s password.');
    }
    final paper = receiptSerial(lastPaperReceipt.trim());
    if (lastPaperReceipt.trim().isEmpty || paper == 0) {
      throw const RestoreRefused(
        'Type the number on the last receipt printed, e.g. R-000061.',
      );
    }
    final now = clock.now();
    final floor = [
      refused.live.nextReceiptNumber,
      receiptSerial(refused.live.figures.lastReceipt) + 1,
      receiptSerial(refused.mark.figures.lastReceipt) + 1,
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
        ),
      ),
    );
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
      },
    );
  });
  await writeMark(mark.withoutPending());
}
