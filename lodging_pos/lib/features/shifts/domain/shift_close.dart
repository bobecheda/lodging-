/// Shift close (FD-11): the cash count, the variance and who may close.
/// Pure Dart.
///
/// The count is blind: the receptionist enters it before seeing what's
/// expected. A recount is allowed; the first count is kept beside the final
/// one, so the supervisor sees both.
library;

import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/money/kes.dart';
import 'shift_rules.dart';

/// What a close records, whole KES.
final class CloseFigures {
  const CloseFigures({
    required this.expectedCash,
    required this.expectedPaybill,
    required this.firstCount,
    required this.counted,
  });

  /// Float plus net cash (payments less cash refund payouts).
  final int expectedCash;

  /// Net M-Pesa, for the owner to compare with the statement.
  final int expectedPaybill;

  /// The first, blind count.
  final int firstCount;

  /// The final count (after any recount).
  final int counted;

  /// Negative: short. Positive: over.
  int get variance => counted - expectedCash;
}

CloseFigures closeFigures(
  ShiftTakings takings, {
  required int openingFloat,
  required int firstCount,
  required int counted,
}) => CloseFigures(
  expectedCash: takings.expectedCash(openingFloat: openingFloat),
  expectedPaybill: takings.expectedPaybill,
  firstCount: firstCount,
  counted: counted,
);

/// `Exact`, `Short KES 200` or `Over KES 50`.
String varianceLabel(int variance) => switch (variance) {
  0 => 'Exact',
  < 0 => 'Short ${formatKes(-variance)}',
  _ => 'Over ${formatKes(variance)}',
};

/// Null if [amount] can be the cash counted.
String? countError(int? amount) {
  if (amount == null) return 'Enter the cash you counted.';
  if (amount < 0) return 'The count cannot be negative.';
  return null;
}

const closeNoteMax = 200;

/// Null if [note] is fine for [variance]: required when the cash is short
/// or over, at most [closeNoteMax] characters.
String? closeNoteError(String note, int variance) {
  final n = note.trim();
  if (n.length > closeNoteMax) {
    return 'Use at most $closeNoteMax characters.';
  }
  if (variance != 0 && n.isEmpty) {
    return 'Say why the cash is ${variance < 0 ? 'short' : 'over'}.';
  }
  return null;
}

/// Whether the Shifts screen highlights [variance]: more than 1% of
/// the shift's takings (the PRD's target), or any variance with no takings.
bool highVariance(int variance, {required int takings}) =>
    variance != 0 && variance.abs() * 100 > takings;

/// `first count KES 4,800 → recounted KES 5,000`, or null without a
/// recount that changed the figure.
String? recountLine(int firstCount, int counted) => firstCount == counted
    ? null
    : 'first count ${formatKes(firstCount)} → recounted ${formatKes(counted)}';

/// `closed by Grace Supervisor for Mary Wanjiku’s shift`, or null when the
/// shift's own user closed it.
String? closedByLine({required String closer, required String owner}) =>
    closer == owner ? null : 'closed by $closer for $owner’s shift';

/// Whether [user] may close the shift of [shiftUserId]: their own with
/// [Permission.closeShift], anyone else's with
/// [Permission.closeOtherShifts] (the supervisor today; a receptionist's
/// "handover close" later, by editing only the permission map).
bool mayCloseShift(UserAccount user, {required String shiftUserId}) =>
    user.id == shiftUserId
    ? can(user, Permission.closeShift)
    : can(user, Permission.closeOtherShifts);

/// Null if the takings are still what the review showed; otherwise why the
/// close must be checked again.
String? closeChange(ShiftTakings shown, ShiftTakings now) {
  bool same(MethodTakings a, MethodTakings b) =>
      a.received == b.received && a.refunded == b.refunded;
  if (same(shown.cash, now.cash) && same(shown.paybill, now.paybill)) {
    return null;
  }
  return 'A payment came in since you counted. Check the figures and close '
      'again.';
}
