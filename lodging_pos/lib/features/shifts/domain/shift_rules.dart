import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../payments/domain/payment_rules.dart';
import 'shift.dart';

/// Null if valid. The float is whole KES and may be zero.
String? openingFloatError(int? amount) {
  if (amount == null) return 'Enter the opening cash float';
  if (amount < 0) return 'The float cannot be negative';
  return null;
}

/// What a signed-in user must do about shifts before working.
sealed class ShiftStart {
  const ShiftStart();
}

/// Ready to work. [shift] is the user's own open shift, or null for a user
/// with [Permission.workWithoutShift] who has none (setup needs no shift).
class ShiftReady extends ShiftStart {
  const ShiftReady(this.shift);
  final OpenShift? shift;
}

/// A receptionist's own shift is open: they confirm it ("Continue my
/// shift") before working, seeing what has been taken so far.
class ResumeShift extends ShiftStart {
  const ResumeShift(this.shift);
  final OpenShift shift;
}

/// A receptionist with no open shift on this device must open one.
class OpenNewShift extends ShiftStart {
  const OpenNewShift();
}

/// Another receptionist's shift is still open on this device.
class ShiftBlocked extends ShiftStart {
  const ShiftBlocked(this.openShift);
  final OpenShift openShift;
}

/// [openShift] is the open shift on this device, if any (at most one).
/// [resumeConfirmed] is true once the user has continued (or just opened)
/// their shift in this sign-in.
ShiftStart shiftStartFor({
  required OpenShift? openShift,
  required UserAccount user,
  bool resumeConfirmed = false,
}) {
  final own = openShift?.userId == user.id ? openShift : null;
  if (can(user, Permission.workWithoutShift)) return ShiftReady(own);
  if (openShift == null) return const OpenNewShift();
  if (own != null) return resumeConfirmed ? ShiftReady(own) : ResumeShift(own);
  // Sprint 1 has no shift close, so this blocks a second receptionist until
  // the first one's shift is closed. FD-11 (shift close) is what unblocks it.
  return ShiftBlocked(openShift);
}

/// BR-12: every check-in, extension, late-checkout charge, payment and refund
/// payout belongs to an open shift.
class NoOpenShift implements Exception {
  const NoOpenShift();

  @override
  String toString() => 'Open a shift before taking payments';
}

/// Returns the shift a payment must use, or throws [NoOpenShift].
OpenShift requireOpenShift(OpenShift? shift) {
  if (shift == null) throw const NoOpenShift();
  return shift;
}

/// One method's money in a shift, whole KES.
final class MethodTakings {
  const MethodTakings({required this.received, required this.refunded});

  /// Payments taken.
  final int received;

  /// Refunds paid out.
  final int refunded;

  int get net => received - refunded;
}

/// A payment or refund payout counted in a shift's totals.
typedef MoneyLine = ({String id, int amount, PaymentMethod method});

/// What a shift has taken so far: received, refunded and net, for cash and
/// Paybill ("M-Pesa") separately, so refunds stay visible.
final class ShiftTakings {
  const ShiftTakings({required this.cash, required this.paybill});

  final MethodTakings cash;
  final MethodTakings paybill;

  int get received => cash.received + paybill.received;
  int get refunded => cash.refunded + paybill.refunded;
  int get net => cash.net + paybill.net;

  /// Cash that should be in the drawer: the float plus net cash. Shift-close
  /// variance (FD-11) is counted against this.
  int expectedCash({required int openingFloat}) => openingFloat + cash.net;

  /// What the Paybill account should show for the shift.
  int get expectedPaybill => paybill.net;
}

/// Totals a shift's [payments] and [refundPayouts] by method (BR-8b,
/// BR-11). Voided payments and voided payouts never count. Only paid refunds
/// are passed in: a requested or approved refund moves no money.
ShiftTakings takingsFrom({
  required Iterable<MoneyLine> payments,
  Iterable<MoneyLine> refundPayouts = const [],
  Set<String> voidedPaymentIds = const {},
  Set<String> voidedRefundIds = const {},
}) {
  int sum(Iterable<MoneyLine> lines, Set<String> voided, PaymentMethod m) => [
    for (final l in lines)
      if (l.method == m && !voided.contains(l.id)) l.amount,
  ].fold(0, (a, b) => a + b);

  MethodTakings of(PaymentMethod m) => MethodTakings(
    received: sum(payments, voidedPaymentIds, m),
    refunded: sum(refundPayouts, voidedRefundIds, m),
  );

  return ShiftTakings(
    cash: of(PaymentMethod.cash),
    paybill: of(PaymentMethod.paybill),
  );
}
