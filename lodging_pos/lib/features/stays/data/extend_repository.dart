import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../../core/settings/setting_defaults.dart';
import '../../payments/data/payment_writes.dart';
import '../../payments/domain/payment_rules.dart';
import '../../setup/domain/prices_settings.dart';
import '../../shifts/domain/shift_rules.dart';
import '../domain/check_out.dart';
import '../domain/extend.dart';
import 'check_out_repository.dart';

/// What the panel showed when the receptionist pressed Extend.
final class ExtendRequest {
  const ExtendRequest({
    required this.stayId,
    required this.nights,
    required this.shownPaidUntil,
    required this.method,
    required this.mpesaCode,
  });

  final String stayId;
  final int nights;

  /// The stay's paid_until the panel worked from (UTC).
  final DateTime shownPaidUntil;
  final PaymentMethod? method;
  final String? mpesaCode;
}

/// The extension couldn't be saved; [message] says why.
class ExtendRefused implements Exception {
  const ExtendRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A saved extension: its payment (the receipt) and the new paid_until.
final class ExtendResult {
  const ExtendResult({
    required this.paymentId,
    required this.nights,
    required this.newPaidUntil,
  });

  final String paymentId;
  final int nights;

  /// UTC.
  final DateTime newPaidUntil;
}

/// Extending a stay (FD-7) in one transaction through writeWithAudit, in
/// the user's own open shift (BR-12): an `extension` charge and paid_until
/// moved to its end (`stay.extend`), one payment (`payment.create`) and the
/// next receipt number. What the panel showed is checked again inside.
class ExtendRepository {
  ExtendRepository(this._db, this._audit)
    : _stays = CheckOutRepository(_db, _audit);

  final AppDatabase _db;
  final AuditWriter _audit;
  final CheckOutRepository _stays;

  /// Throws [NotPermitted], [NoOpenShift], [ExtendRefused] or
  /// [InvalidLatePayment] (the method or M-Pesa code).
  Future<ExtendResult> extend(UserAccount user, ExtendRequest r) async {
    requirePermission(user, Permission.extendStay);
    return _audit.writeWithAudit(
      action: 'stay.extend',
      userId: user.id,
      body: (w) async {
        final shift = await ownOpenShift(_db, w, user.id);
        if (shift == null) throw const NoOpenShift();

        final detail = await _stays.stay(r.stayId);
        if (!detail.isActive) {
          throw const ExtendRefused('This guest has already checked out.');
        }
        final settings = {
          for (final s in await _db.select(_db.settings).get()) s.key: s.value,
        };
        final grace = graceMinutesFrom(settings[SettingKeys.graceMinutes]);
        final minNights = extendMinNights(detail.stay, w.now, grace);
        final change = extendChange(
          shownPaidUntil: r.shownPaidUntil,
          nowPaidUntil: detail.stay.paidUntil,
          nights: r.nights,
          nowMinNights: minNights,
        );
        if (change != null) throw ExtendRefused(change);
        final nightsProblem = extendNightsError(r.nights, minNights: minNights);
        if (nightsProblem != null) throw ExtendRefused(nightsProblem);

        final method = r.method;
        final code = method == PaymentMethod.paybill && r.mpesaCode != null
            ? normalizeMpesaCode(r.mpesaCode!)
            : r.mpesaCode;
        final payProblem = latePaymentError(
          method,
          code,
          codeUsedOn: code == null || code.trim().isEmpty
              ? null
              : await mpesaCodeUse(_db, code),
        );
        if (payProblem != null) throw InvalidLatePayment(payProblem);

        final quote = quoteExtend(detail.stay, r.nights);
        final c = quote.charge;
        final prefix = SettingsInput.fromStored(settings).receiptPrefix;
        final payment = await w.insert(
          _db.payments,
          PaymentsCompanion.insert(
            receiptNumber: await takeReceiptNumber(_db, w, prefix),
            shiftId: shift.id,
            receivedBy: user.id,
            receivedAt: w.now,
            amount: quote.total,
            method: method!.code,
            mpesaCode: Value(method == PaymentMethod.paybill ? code : null),
          ),
          action: 'payment.create',
        );
        await w.insert(
          _db.stayCharges,
          StayChargesCompanion.insert(
            stayId: detail.id,
            paymentId: payment.id,
            kind: c.kind.code,
            nights: c.nights,
            pricePerNight: c.pricePerNight,
            amount: c.amount,
            periodStart: c.periodStart,
            periodEnd: c.periodEnd,
            categoryId: c.categoryId,
            categoryName: c.categoryName,
          ),
        );
        // paid_until is always the latest charge's end (BR-7).
        await w.update(
          _db.stays,
          detail.id,
          StaysCompanion(paidUntil: Value(c.periodEnd)),
        );
        return ExtendResult(
          paymentId: payment.id,
          nights: c.nights,
          newPaidUntil: c.periodEnd,
        );
      },
    );
  }
}
