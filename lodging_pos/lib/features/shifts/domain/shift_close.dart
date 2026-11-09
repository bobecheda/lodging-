/// Shift close (FD-11, Story B): the blind cash count, the variance and who
/// may close. Pure Dart.
///
/// The count is blind: whoever closes never sees what's expected, and a
/// receptionist never sees it at all (`viewShiftTotals`). A count that
/// matches (within `shift_count_tolerance`, UB40: 0, so overs too) closes the
/// shift. One that doesn't is saved at once and asks for one recount, with
/// no amount and no short or over; a recount that still doesn't match needs
/// a reason, and the shift closes anyway, needing review (BR-12 is never
/// blocked). Leaving and coming back never gives a third try: each count is
/// on the shift before the next is asked for.
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

/// Whether [count] matches [expected]: within [tolerance] either way
/// (`shift_count_tolerance`, owner-only; UB40 keeps 0).
bool countMatches(int count, {required int expected, int tolerance = 0}) =>
    (count - expected).abs() <= tolerance;

/// Where a close is: the first count, the one recount, or the reason.
enum CountStage { first, recount, reason }

/// The stage from what the open shift already holds: its saved first
/// count, and its saved recount.
CountStage countStage({required int? firstCount, required int? recount}) =>
    firstCount == null
    ? CountStage.first
    : recount == null
    ? CountStage.recount
    : CountStage.reason;

/// What the counter is told after a first count that doesn't match.
const countAgainMessage = 'Your count doesn’t match. Count the cash again.';

/// After a recount that still doesn't match.
const reasonNeededMessage =
    'Your count still doesn’t match. Say why, then close the shift.';

/// Null if [reason] can close a shift whose count didn't match: required,
/// at most [closeNoteMax] characters. Never says short or over.
String? closeReasonError(String reason) {
  final r = reason.trim();
  if (r.isEmpty) return 'Say why the count may be different.';
  if (r.length > closeNoteMax) return 'Use at most $closeNoteMax characters.';
  return null;
}

/// The first count missed, the recount matched: recorded, shown to the
/// reviewer and counted in the receptionist's history.
bool matchedOnRecount({
  required int firstCount,
  required int counted,
  required bool needsReview,
}) => !needsReview && firstCount != counted;

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
