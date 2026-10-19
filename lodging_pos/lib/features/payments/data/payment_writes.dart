import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/database/database.dart';
import '../../receipts/domain/receipt_number.dart';
import '../domain/payment_rules.dart';

/// Reads and writes every payment shares (check-in, late checkout, and later
/// extensions and refund payouts). Call them inside a writeWithAudit body,
/// so they read and write the same transaction.

/// Where [code] was already used, in a payment or a refund payout (BR-10).
/// Both columns are COLLATE NOCASE, so the match ignores case.
Future<MpesaCodeUse?> mpesaCodeUse(AppDatabase db, String code) async {
  final payment =
      await (db.select(db.payments)
            ..where((p) => p.mpesaCode.equals(code))
            ..limit(1))
          .getSingleOrNull();
  if (payment != null) {
    return MpesaCodeUse(
      receiptNumber: payment.receiptNumber,
      at: payment.receivedAt,
    );
  }
  final refund =
      await (db.select(db.refunds)
            ..where((p) => p.mpesaCode.equals(code))
            ..limit(1))
          .getSingleOrNull();
  if (refund != null) {
    return MpesaCodeUse(
      receiptNumber: refund.receiptNumber!,
      at: refund.paidAt!,
      isRefund: true,
    );
  }
  return null;
}

/// Takes this device's next receipt number. Gap-free: the counter moves in
/// the same transaction as the payment, and isn't audited or synced.
Future<String> takeReceiptNumber(
  AppDatabase db,
  AuditedWrites w,
  String prefix,
) async {
  final counter = await (db.select(
    db.receiptCounter,
  )..where((c) => c.deviceId.equals(w.deviceId))).getSingle();
  await w.update(
    db.receiptCounter,
    w.deviceId,
    ReceiptCounterCompanion(nextNumber: Value(counter.nextNumber + 1)),
  );
  return formatReceiptNumber(prefix, counter.nextNumber);
}

/// [userId]'s own open shift on this device, which money must go into
/// (BR-12); null if they have none.
Future<ShiftRow?> ownOpenShift(
  AppDatabase db,
  AuditedWrites w,
  String userId,
) =>
    (db.select(db.shifts)..where(
          (s) =>
              s.status.equals('open') &
              s.deviceId.equals(w.deviceId) &
              s.userId.equals(userId),
        ))
        .getSingleOrNull();
