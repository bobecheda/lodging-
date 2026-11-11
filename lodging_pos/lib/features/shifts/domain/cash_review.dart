/// Reviewing the drawer's gaps (Story B3): a shift close or a drawer count
/// recorded with `needs_review` is approved or rejected, once, by someone
/// who may. Pure Dart.
///
/// - Only users with [Permission.reviewCash] (the supervisor and the owner)
///   decide; a receptionist never does.
/// - Nobody decides an item that names them (the shift's user or its
///   closer; a count's counter or the one present).
/// - An item that names someone who could review cash (a supervisor's
///   shift, close or count, or a supervisor present) is the owner's only
///   ([Permission.reviewSupervisorCash]).
/// - The owner decides the gaps from the owner's own counts.
/// - A rejection needs a reason (at most 200 characters).
///
/// The decision is the cloud's (`decide_cash_review`), pulled by the desk;
/// these rules are checked on the desk first and again in the cloud.
library;

import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/money/kes.dart';
import '../../setup/domain/staff.dart' show roleAllows;
import 'shift_close.dart' show closeNoteMax;

enum ReviewTargetKind {
  shift('shift', 'shift'),
  drawerEvent('drawer_event', 'drawer');

  const ReviewTargetKind(this.code, this.auditEntity);

  /// As stored in `cash_reviews.target_type`.
  final String code;

  /// The audit actions' entity: `shift.review_approve`,
  /// `drawer.review_reject`.
  final String auditEntity;

  static ReviewTargetKind parse(String code) =>
      values.firstWhere((k) => k.code == code);
}

enum ReviewDecision {
  approved('approved'),
  rejected('rejected');

  const ReviewDecision(this.code);
  final String code;

  static ReviewDecision parse(String code) =>
      values.firstWhere((d) => d.code == code);
}

enum ReviewStatus { notNeeded, awaiting, approved, rejected }

/// Derived, never stored: no review needed, awaiting, or the decision.
ReviewStatus reviewStatus({
  required bool needsReview,
  ReviewDecision? decision,
}) => !needsReview
    ? ReviewStatus.notNeeded
    : switch (decision) {
        null => ReviewStatus.awaiting,
        ReviewDecision.approved => ReviewStatus.approved,
        ReviewDecision.rejected => ReviewStatus.rejected,
      };

/// What a review needs to know about its target.
final class ReviewTarget {
  const ReviewTarget({
    required this.kind,
    required this.id,
    required this.needsReview,
    required this.named,
    this.counter,
  });

  final ReviewTargetKind kind;
  final String id;
  final bool needsReview;

  /// Everyone it names: a shift's user and closer, or a count's counter and
  /// the one present.
  final List<UserAccount> named;

  /// A drawer count's counter; null for a shift.
  final UserAccount? counter;

  /// A count by the owner (who may decide it, though named).
  bool get countedByOwner =>
      counter != null && roleAllows(counter!, Permission.reviewSupervisorCash);

  /// It names someone who could review cash themselves.
  bool get namesReviewer =>
      named.any((u) => roleAllows(u, Permission.reviewCash));
}

/// A review rule refused the decision; [message] is shown.
class CashReviewProblem implements Exception {
  const CashReviewProblem(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Why [by] can't decide [target] ([decided]: its decision, if any), or
/// null. A screen shows it instead of the buttons; [checkReview] enforces
/// it.
String? reviewBlocker(
  ReviewTarget target,
  UserAccount by, {
  ReviewDecision? decided,
}) {
  if (!can(by, Permission.reviewCash)) return 'You can’t review cash.';
  if (!target.needsReview) return 'Nothing to review here.';
  if (decided != null) return 'Already decided.';
  if (target.countedByOwner) {
    return can(by, Permission.reviewSupervisorCash)
        ? null
        : 'The owner decides gaps from the owner’s own counts.';
  }
  if (target.named.any((u) => u.id == by.id)) {
    return 'You’re named in this, so someone else decides.';
  }
  if (target.namesReviewer && !can(by, Permission.reviewSupervisorCash)) {
    return 'A supervisor is named in this: the owner decides.';
  }
  return null;
}

/// [by] may decide [target] as [decision], with [reason] when rejecting.
/// Throws [NotPermitted] or [CashReviewProblem].
void checkReview(
  ReviewTarget target, {
  required UserAccount by,
  required ReviewDecision decision,
  String? reason,
  ReviewDecision? decided,
}) {
  requirePermission(by, Permission.reviewCash);
  if (reviewBlocker(target, by, decided: decided) case final p?) {
    throw CashReviewProblem(p);
  }
  if (decision == ReviewDecision.rejected) {
    final r = reason?.trim() ?? '';
    if (r.isEmpty) throw const CashReviewProblem('Say why you reject it.');
    if (r.length > closeNoteMax) {
      throw const CashReviewProblem('Use at most $closeNoteMax characters.');
    }
  }
}

/// `shift.review_approve`, `drawer.review_reject`, …
String reviewAction(ReviewTargetKind kind, ReviewDecision decision) =>
    '${kind.auditEntity}.review_'
    '${decision == ReviewDecision.approved ? 'approve' : 'reject'}';

/// A rejected review, for the owner's Needs your attention (desk and
/// phone).
final class RejectedReview {
  const RejectedReview({
    required this.kind,
    required this.targetId,
    required this.whose,
    required this.decidedBy,
    required this.reason,
    required this.decidedAt,
    required this.gap,
  });

  final ReviewTargetKind kind;
  final String targetId;

  /// `Mary Desk’s shift close`, `Grace Supervisor’s drawer check`.
  final String whose;

  /// The decider's full name.
  final String decidedBy;
  final String reason;

  /// UTC.
  final DateTime decidedAt;

  /// Counted − expected: negative is short.
  final int gap;

  String get title => 'Cash review rejected';
  String get subtitle => '$whose · by $decidedBy: $reason';

  /// `KES 100 short`, `KES 50 over`, `Exact`.
  String get figure => gap == 0
      ? 'Exact'
      : '${formatKes(gap.abs())} ${gap < 0 ? 'short' : 'over'}';
}
