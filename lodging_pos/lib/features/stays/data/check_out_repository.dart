import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../../core/settings/setting_defaults.dart';
import '../../guests/domain/guest.dart';
import '../../payments/data/payment_writes.dart';
import '../../payments/domain/payment_rules.dart';
import '../../refunds/domain/refund.dart';
import '../../setup/domain/prices_settings.dart';
import '../../shifts/domain/shift_rules.dart';
import '../domain/check_out.dart';
import '../domain/stay_rules.dart';

/// One of a stay's charges and the receipt that paid it.
typedef PaidCharge = ({ChargeLine charge, String receiptNumber});

/// A stay as the bed panel shows it.
final class StayDetail {
  const StayDetail({
    required this.stay,
    required this.isActive,
    required this.checkedOutAt,
    required this.guest,
    required this.roomNumber,
    required this.bedLabel,
    required this.charges,
  });

  /// The rules' view: every charge in order, the first the check-in.
  final Stay stay;
  final bool isActive;

  /// UTC; null while active.
  final DateTime? checkedOutAt;
  final Guest guest;

  /// As let (v3).
  final String roomNumber;
  final String bedLabel;
  final List<PaidCharge> charges;

  String get id => stay.id;
  String get bedId => stay.bedId;
}

/// What the panel showed when the receptionist confirmed it.
final class CheckOutRequest {
  const CheckOutRequest({
    required this.stayId,
    required this.shown,
    this.method,
    this.mpesaCode,
  });

  final String stayId;
  final CheckoutTerms shown;

  /// For a late checkout's charge only.
  final PaymentMethod? method;
  final String? mpesaCode;
}

/// Something changed since the panel showed it: [message] says what and
/// what to do.
class CheckOutRefused implements Exception {
  const CheckOutRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A late checkout's payment can't be taken this way (method or M-Pesa
/// code); [message] goes under the code field.
class InvalidLatePayment implements Exception {
  const InvalidLatePayment(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A done checkout, for the panel's result.
final class CheckOutResult {
  const CheckOutResult({
    required this.stayId,
    required this.checkedOutAt,
    required this.terms,
    required this.guestName,
    required this.guestPhone,
    required this.roomNumber,
    required this.bedLabel,
    this.paymentId,
  });

  final String stayId;

  /// UTC.
  final DateTime checkedOutAt;

  /// What was done: free, with a refund request, or with a late charge.
  final CheckoutTerms terms;
  final String guestName;

  /// Stored form; shown masked.
  final String guestPhone;
  final String roomNumber;
  final String bedLabel;

  /// The late charge's payment (its receipt), if any.
  final String? paymentId;
}

/// Checkout (FD-8) in one transaction through writeWithAudit, in the user's
/// own open shift (BR-12):
/// - late: a `late_checkout` charge with its own payment and receipt
///   (`stay.late_charge`, `payment.create`), moving paid_until (BR-7a);
/// - early: a refund **request** for the nights not started
///   (`refund.request`), for the owner's approval (BR-8a);
/// - always: the stay closed and the bed not cleaned (`stay.check_out`,
///   BR-9).
/// The terms are worked out again at the moment of saving and must match
/// what the panel showed.
class CheckOutRepository {
  CheckOutRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditWriter _audit;

  /// [stayId] as the panel shows it, watched: a checkout elsewhere shows at
  /// once.
  Stream<StayDetail> watchStay(String stayId) => (_db.select(
    _db.stays,
  )..where((s) => s.id.equals(stayId))).watchSingle().asyncMap(_detail);

  Future<StayDetail> stay(String stayId) async => _detail(
    await (_db.select(
      _db.stays,
    )..where((s) => s.id.equals(stayId))).getSingle(),
  );

  Future<StayDetail> _detail(StayRow row) async {
    final rows =
        await (_db.select(_db.stayCharges).join([
                innerJoin(
                  _db.payments,
                  _db.payments.id.equalsExp(_db.stayCharges.paymentId),
                ),
              ])
              ..where(_db.stayCharges.stayId.equals(row.id))
              ..orderBy([
                OrderingTerm.asc(_db.stayCharges.periodStart),
                OrderingTerm.asc(_db.stayCharges.createdAt),
              ]))
            .get();
    final charges = <PaidCharge>[
      for (final r in rows)
        (
          charge: _line(r.readTable(_db.stayCharges)),
          receiptNumber: r.readTable(_db.payments).receiptNumber,
        ),
    ];
    var stay = Stay.fromCheckIn(
      id: row.id,
      bedId: row.bedId,
      charge: charges.first.charge,
    );
    for (final c in charges.skip(1)) {
      stay = stay.withCharge(c.charge);
    }
    final guest = await (_db.select(
      _db.guests,
    )..where((g) => g.id.equals(row.guestId))).getSingle();
    return StayDetail(
      stay: stay,
      isActive: row.status == 'active',
      checkedOutAt: row.checkedOutAt,
      guest: Guest(
        id: guest.id,
        fullName: guest.fullName,
        phone: guest.phone,
        idType: guest.idType == null ? null : IdType.parse(guest.idType!),
        idNumber: guest.idNumber,
        registeredAt: guest.createdAt,
      ),
      roomNumber: row.roomNumber,
      bedLabel: row.bedLabel,
      charges: charges,
    );
  }

  static ChargeLine _line(StayChargeRow c) => ChargeLine(
    kind: ChargeKind.parse(c.kind),
    nights: c.nights,
    pricePerNight: c.pricePerNight,
    categoryId: c.categoryId,
    categoryName: c.categoryName,
    periodStart: c.periodStart,
    periodEnd: c.periodEnd,
  );

  /// Saves the checkout. Throws [NotPermitted], [NoOpenShift],
  /// [CheckOutRefused] or [InvalidLatePayment].
  Future<CheckOutResult> checkOut(UserAccount user, CheckOutRequest r) async {
    requirePermission(user, Permission.checkOut);
    return _audit.writeWithAudit(
      action: 'stay.check_out',
      userId: user.id,
      body: (w) async {
        final shift = await ownOpenShift(_db, w, user.id);
        if (shift == null) throw const NoOpenShift();

        final detail = await stay(r.stayId);
        if (!detail.isActive) {
          throw const CheckOutRefused('This guest has already checked out.');
        }
        final settings = {
          for (final s in await _db.select(_db.settings).get()) s.key: s.value,
        };
        final terms = checkoutTerms(
          detail.stay,
          w.now,
          graceMinutesFrom(settings[SettingKeys.graceMinutes]),
        );
        final change = checkoutChange(r.shown, terms);
        if (change != null) throw CheckOutRefused(change);

        String? paymentId;
        switch (terms) {
          case LateCheckout(:final charge):
            final method = r.method;
            final code = method == PaymentMethod.paybill && r.mpesaCode != null
                ? normalizeMpesaCode(r.mpesaCode!)
                : r.mpesaCode;
            final problem = latePaymentError(
              method,
              code,
              codeUsedOn: code == null || code.trim().isEmpty
                  ? null
                  : await mpesaCodeUse(_db, code),
            );
            if (problem != null) throw InvalidLatePayment(problem);
            final prefix = SettingsInput.fromStored(settings).receiptPrefix;
            final payment = await w.insert(
              _db.payments,
              PaymentsCompanion.insert(
                receiptNumber: await takeReceiptNumber(_db, w, prefix),
                shiftId: shift.id,
                receivedBy: user.id,
                receivedAt: w.now,
                amount: charge.amount,
                method: method!.code,
                mpesaCode: Value(method == PaymentMethod.paybill ? code : null),
              ),
              action: 'payment.create',
            );
            paymentId = payment.id;
            await w.insert(
              _db.stayCharges,
              StayChargesCompanion.insert(
                stayId: detail.id,
                paymentId: payment.id,
                kind: charge.kind.code,
                nights: charge.nights,
                pricePerNight: charge.pricePerNight,
                amount: charge.amount,
                periodStart: charge.periodStart,
                periodEnd: charge.periodEnd,
                categoryId: charge.categoryId,
                categoryName: charge.categoryName,
              ),
              action: 'stay.late_charge',
            );
            // paid_until is always the latest charge's end (BR-7a).
            await w.update(
              _db.stays,
              detail.id,
              StaysCompanion(paidUntil: Value(charge.periodEnd)),
              action: 'stay.late_charge',
            );
          case EarlyCheckout(:final refund):
            final request = requestRefund(
              refund,
              id: const Uuid().v4(),
              stayId: detail.id,
              by: user,
              at: w.now,
            );
            await w.insert(
              _db.refunds,
              RefundsCompanion.insert(
                id: Value(request.id),
                stayId: request.stayId,
                nights: request.nights,
                pricePerNight: request.pricePerNight,
                amount: request.amount,
                requestedBy: request.requestedBy,
                requestedAt: request.requestedAt,
              ),
              action: 'refund.request',
            );
          case OnTimeCheckout():
            break;
        }

        await w.update(
          _db.stays,
          detail.id,
          StaysCompanion(
            status: const Value('closed'),
            checkedOutAt: Value(w.now),
            checkedOutBy: Value(user.id),
          ),
        );
        // BR-9: only a finished housekeeping task makes it clean again.
        await w.update(
          _db.beds,
          detail.bedId,
          const BedsCompanion(cleanliness: Value('not_cleaned')),
        );

        return CheckOutResult(
          stayId: detail.id,
          checkedOutAt: w.now,
          terms: terms,
          guestName: detail.guest.fullName,
          guestPhone: detail.guest.phone,
          roomNumber: detail.roomNumber,
          bedLabel: detail.bedLabel,
          paymentId: paymentId,
        );
      },
    );
  }

  /// The grace setting, for working out the terms on screen.
  Future<int> graceMinutes() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(SettingKeys.graceMinutes))).getSingleOrNull();
    return graceMinutesFrom(row?.value);
  }
}
