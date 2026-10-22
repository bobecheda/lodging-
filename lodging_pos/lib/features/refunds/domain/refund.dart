/// Refunds of unused prepaid nights (BR-8, BR-8a, BR-8b). Pure Dart.
///
/// requested ──(owner approves)──► approved ──(payout)──► paid
///     └──────(owner rejects + reason)──► rejected
///
/// The status is derived from the decision and payout, never stored. The
/// amount is set from the stay rules at checkout and nothing here can change
/// it.
library;

import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/contacts/phone.dart';
import '../../payments/domain/payment_rules.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_rules.dart';
import '../../stays/domain/stay_rules.dart';

enum RefundStatus { requested, approved, rejected, paid }

/// As stored in `refund_decisions.decision`.
enum RefundDecisionKind {
  approved,
  rejected;

  String get code => name;

  static RefundDecisionKind parse(String code) =>
      values.firstWhere((k) => k.code == code);
}

/// One `refund_decisions` row: written once, never changed.
final class RefundDecision {
  const RefundDecision({
    required this.kind,
    required this.note,
    required this.decidedBy,
    required this.decidedAt,
  });

  final RefundDecisionKind kind;

  /// Required for a rejection.
  final String? note;
  final String decidedBy;
  final DateTime decidedAt;
}

/// The payout fields of a `refunds` row, set once when paid.
final class RefundPayout {
  const RefundPayout({
    required this.method,
    required this.mpesaCode,
    required this.shiftId,
    required this.paidBy,
    required this.paidAt,
    this.phone,
  });

  final PaymentMethod method;

  /// The M-Pesa code of the money sent back, for a Paybill payout.
  final String? mpesaCode;

  /// The phone an M-Pesa payout was sent to (stored like a guest phone);
  /// null for cash.
  final String? phone;

  /// The open shift that paid it, whose totals it reduces.
  final String shiftId;
  final String paidBy;
  final DateTime paidAt;
}

final class Refund {
  const Refund({
    required this.id,
    required this.stayId,
    required this.nights,
    required this.pricePerNight,
    required this.amount,
    required this.requestedBy,
    required this.requestedAt,
    this.decision,
    this.payout,
  });

  final String id;
  final String stayId;
  final int nights;
  final int pricePerNight;

  /// Whole KES, = nights × price_per_night.
  final int amount;
  final String requestedBy;
  final DateTime requestedAt;
  final RefundDecision? decision;
  final RefundPayout? payout;

  RefundStatus get status => switch ((decision?.kind, payout)) {
    (_, RefundPayout()) => RefundStatus.paid,
    (null, null) => RefundStatus.requested,
    (RefundDecisionKind.approved, null) => RefundStatus.approved,
    (RefundDecisionKind.rejected, null) => RefundStatus.rejected,
  };

  Refund _with({RefundDecision? decision, RefundPayout? payout}) => Refund(
    id: id,
    stayId: stayId,
    nights: nights,
    pricePerNight: pricePerNight,
    amount: amount,
    requestedBy: requestedBy,
    requestedAt: requestedAt,
    decision: decision ?? this.decision,
    payout: payout ?? this.payout,
  );
}

/// A refund rule refused the action; [message] is shown to the user.
class RefundRuleViolation implements Exception {
  const RefundRuleViolation(this.message);
  final String message;

  @override
  String toString() => message;
}

/// BR-8a: the request created by an early checkout, for the calculated
/// [terms].
Refund requestRefund(
  RefundTerms terms, {
  required String id,
  required String stayId,
  required UserAccount by,
  required DateTime at,
}) {
  requirePermission(by, Permission.requestRefund);
  return Refund(
    id: id,
    stayId: stayId,
    nights: terms.nights,
    pricePerNight: terms.pricePerNight,
    amount: terms.amount,
    requestedBy: by.id,
    requestedAt: at,
  );
}

void _requireUndecided(Refund refund) {
  if (refund.status != RefundStatus.requested) {
    throw const RefundRuleViolation('This refund has already been decided.');
  }
}

/// BR-8a: approves [refund] as requested; the amount can't be changed. The
/// user who requested it can't approve it (rejecting it is allowed: no
/// money goes out).
Refund approveRefund(
  Refund refund, {
  required UserAccount by,
  required DateTime at,
}) {
  requirePermission(by, Permission.approveRefund);
  _requireUndecided(refund);
  if (refund.requestedBy == by.id) {
    throw const RefundRuleViolation(
      'You requested this refund, so someone else must approve it.',
    );
  }
  return refund._with(
    decision: RefundDecision(
      kind: RefundDecisionKind.approved,
      note: null,
      decidedBy: by.id,
      decidedAt: at,
    ),
  );
}

/// BR-8a: rejects [refund]; [note] (the reason) is required.
Refund rejectRefund(
  Refund refund, {
  required UserAccount by,
  required String? note,
  required DateTime at,
}) {
  requirePermission(by, Permission.approveRefund);
  _requireUndecided(refund);
  final reason = note?.trim() ?? '';
  if (reason.isEmpty) {
    throw const RefundRuleViolation('Give a reason for rejecting the refund.');
  }
  return refund._with(
    decision: RefundDecision(
      kind: RefundDecisionKind.rejected,
      note: reason,
      decidedBy: by.id,
      decidedAt: at,
    ),
  );
}

/// BR-8b: records paying out an approved [refund] from the cash drawer or
/// the Paybill account, in the open [shift]. [codeInUse] says whether
/// [mpesaCode] is already on a payment or refund payout. An M-Pesa payout
/// also needs [sendTo], the phone the money goes to (the guest's, editable;
/// the guest phone rule).
Refund payRefund(
  Refund refund, {
  required UserAccount by,
  required OpenShift? shift,
  required PaymentMethod method,
  required String? mpesaCode,
  required bool codeInUse,
  required DateTime at,
  String? sendTo,
  MpesaCodeUse? codeUsedOn,
}) {
  requirePermission(by, Permission.payRefund);
  final open = requireOpenShift(shift);
  switch (refund.status) {
    case RefundStatus.approved:
      break;
    case RefundStatus.requested:
      throw const RefundRuleViolation('This refund has not been approved yet.');
    case RefundStatus.rejected:
      throw const RefundRuleViolation('This refund was rejected.');
    case RefundStatus.paid:
      throw const RefundRuleViolation('This refund has already been paid.');
  }
  final codeProblem = mpesaCodeError(
    method,
    mpesaCode,
    codeInUse: codeInUse,
    usedOn: codeUsedOn,
  );
  if (codeProblem != null) throw InvalidMpesaCode(codeProblem);
  final phoneProblem = payoutPhoneError(method, sendTo);
  if (phoneProblem != null) throw InvalidPayoutPhone(phoneProblem);
  final paybill = method == PaymentMethod.paybill;
  return refund._with(
    payout: RefundPayout(
      method: method,
      mpesaCode: paybill ? normalizeMpesaCode(mpesaCode!) : null,
      shiftId: open.id,
      paidBy: by.id,
      paidAt: at,
      phone: paybill ? normalizeGuestPhone(sendTo!) : null,
    ),
  );
}

/// Why an M-Pesa payout's "Send to" phone can't be used, or null. Cash
/// needs none.
String? payoutPhoneError(PaymentMethod method, String? sendTo) =>
    method == PaymentMethod.paybill ? guestPhoneError(sendTo ?? '') : null;

/// The "Send to" phone was refused ([payoutPhoneError]).
final class InvalidPayoutPhone implements Exception {
  const InvalidPayoutPhone(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The payouts [shiftId] made, for its totals. Requested, approved-unpaid
/// and rejected refunds move no money and are left out.
List<MoneyLine> refundPayoutsIn(String shiftId, Iterable<Refund> refunds) => [
  for (final r in refunds)
    if (r.payout case final payout? when payout.shiftId == shiftId)
      (id: r.id, amount: r.amount, method: payout.method),
];
