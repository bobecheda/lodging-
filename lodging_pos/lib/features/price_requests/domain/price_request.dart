/// Price change requests (BR-2). Pure Dart.
///
/// waiting ──(owner approves: the price changes)──► approved
///    ├─────(owner rejects + reason)──► rejected
///    └─────(the supervisor withdraws it, or the category closes)──► withdrawn
///
/// The supervisor asks; only the owner changes a price (directly, or by
/// approving). A request keeps the price it was made against, so an
/// approval can't apply a change the owner has since overtaken. The status
/// is derived, never stored.
library;

import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/money/kes.dart';
import '../../setup/domain/bed_category.dart';
import '../../setup/domain/prices_settings.dart';

enum PriceRequestStatus { waiting, approved, rejected, withdrawn }

/// As stored in `price_decisions.decision`.
enum PriceDecisionKind {
  approved,
  rejected;

  String get code => name;

  static PriceDecisionKind parse(String code) =>
      values.firstWhere((k) => k.code == code);
}

/// One `price_decisions` row: written once, never changed.
final class PriceDecision {
  const PriceDecision({
    required this.kind,
    required this.note,
    required this.decidedBy,
    required this.decidedAt,
  });

  final PriceDecisionKind kind;

  /// Required for a rejection.
  final String? note;
  final String decidedBy;
  final DateTime decidedAt;
}

/// The reason stored when closing a category withdraws its request.
const categoryClosedReason = 'Category closed';

/// The withdrawal fields of a `price_requests` row, set once.
final class PriceWithdrawal {
  const PriceWithdrawal({required this.by, required this.at, this.reason});

  /// The supervisor who asked, or the owner who closed the category.
  final String by;
  final DateTime at;

  /// Null when the supervisor withdrew it; [categoryClosedReason] when
  /// closing the category did.
  final String? reason;

  bool get categoryClosed => reason == categoryClosedReason;
}

final class PriceRequest {
  const PriceRequest({
    required this.id,
    required this.categoryId,
    required this.oldPrice,
    required this.newPrice,
    required this.reason,
    required this.requestedBy,
    required this.requestedAt,
    this.decision,
    this.withdrawal,
  });

  final String id;
  final String categoryId;

  /// The category's price when the request was made.
  final int oldPrice;
  final int newPrice;
  final String? reason;
  final String requestedBy;
  final DateTime requestedAt;
  final PriceDecision? decision;
  final PriceWithdrawal? withdrawal;

  PriceRequestStatus get status => switch ((decision?.kind, withdrawal)) {
    (_, PriceWithdrawal()) => PriceRequestStatus.withdrawn,
    (null, null) => PriceRequestStatus.waiting,
    (PriceDecisionKind.approved, null) => PriceRequestStatus.approved,
    (PriceDecisionKind.rejected, null) => PriceRequestStatus.rejected,
  };

  /// KES a night more (or, negative, less) than [oldPrice].
  int get change => newPrice - oldPrice;

  PriceRequest _with({PriceDecision? decision, PriceWithdrawal? withdrawal}) =>
      PriceRequest(
        id: id,
        categoryId: categoryId,
        oldPrice: oldPrice,
        newPrice: newPrice,
        reason: reason,
        requestedBy: requestedBy,
        requestedAt: requestedAt,
        decision: decision ?? this.decision,
        withdrawal: withdrawal ?? this.withdrawal,
      );
}

/// A request rule refused the action; [message] is shown to the user.
class PriceRequestRuleViolation implements Exception {
  const PriceRequestRuleViolation(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The requested price failed [requestedPriceError]; shown under the field.
final class InvalidRequestedPrice implements Exception {
  const InvalidRequestedPrice(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The price changed since the request was made ([staleError]).
final class StalePriceRequest implements Exception {
  const StalePriceRequest(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Why [price] can't be asked for, or null: the owner's price rule
/// (KES 1–100,000), and not the price it already is.
String? requestedPriceError(int? price, {required int currentPrice}) =>
    priceError(price) ??
    (price == currentPrice ? 'That’s already the price.' : null);

const reasonMaxLength = 200;

/// Why [reason] can't be kept, or null. It is optional.
String? requestReasonError(String? reason) =>
    (reason?.trim().length ?? 0) > reasonMaxLength
    ? 'Keep the reason under $reasonMaxLength characters.'
    : null;

/// BR-2: the supervisor asks for [newPrice] on [category]. [open] is the
/// category's request still waiting, if any: one at a time.
PriceRequest requestPriceChange(
  BedCategory category, {
  required String id,
  required int? newPrice,
  required String? reason,
  required UserAccount by,
  required DateTime at,
  required PriceRequest? open,
}) {
  requirePermission(by, Permission.requestPriceChange);
  if (!category.isActive) {
    throw PriceRequestRuleViolation('${category.name} is closed.');
  }
  if (open != null) {
    throw PriceRequestRuleViolation(
      '${category.name} already has a request waiting for the owner.',
    );
  }
  final priceProblem = requestedPriceError(
    newPrice,
    currentPrice: category.pricePerNight,
  );
  if (priceProblem != null) throw InvalidRequestedPrice(priceProblem);
  final reasonProblem = requestReasonError(reason);
  if (reasonProblem != null) throw PriceRequestRuleViolation(reasonProblem);
  final trimmed = reason?.trim() ?? '';
  return PriceRequest(
    id: id,
    categoryId: category.id,
    oldPrice: category.pricePerNight,
    newPrice: newPrice!,
    reason: trimmed.isEmpty ? null : trimmed,
    requestedBy: by.id,
    requestedAt: at,
  );
}

void _requireWaiting(PriceRequest request, {required bool deciding}) {
  switch (request.status) {
    case PriceRequestStatus.waiting:
      return;
    case PriceRequestStatus.withdrawn:
      throw const PriceRequestRuleViolation('This request was withdrawn.');
    case PriceRequestStatus.approved || PriceRequestStatus.rejected:
      throw PriceRequestRuleViolation(
        deciding
            ? 'This request has already been decided.'
            : 'The owner has already decided this request.',
      );
  }
}

/// The supervisor withdraws their own waiting [request].
PriceRequest withdrawPriceRequest(
  PriceRequest request, {
  required UserAccount by,
  required DateTime at,
}) {
  requirePermission(by, Permission.requestPriceChange);
  if (request.requestedBy != by.id) {
    throw const PriceRequestRuleViolation(
      'Only the supervisor who asked can withdraw it.',
    );
  }
  _requireWaiting(request, deciding: false);
  return request._with(
    withdrawal: PriceWithdrawal(by: by.id, at: at),
  );
}

/// Closing the category (the owner's, [Permission.editPrices]) withdraws
/// its waiting [request], so a reopened category starts with none.
PriceRequest withdrawForClosedCategory(
  PriceRequest request, {
  required UserAccount by,
  required DateTime at,
}) {
  requirePermission(by, Permission.editPrices);
  _requireWaiting(request, deciding: false);
  return request._with(
    withdrawal: PriceWithdrawal(
      by: by.id,
      at: at,
      reason: categoryClosedReason,
    ),
  );
}

/// Why [request] can't be approved as asked: [category]'s price has changed
/// since (the owner edited it directly). Null when it hasn't.
String? staleError(PriceRequest request, BedCategory category) =>
    category.pricePerNight == request.oldPrice
    ? null
    : '${category.name} is now ${formatKes(category.pricePerNight)}, not '
          '${formatKesPlain(request.oldPrice)}. Reject this request or ask '
          'for a new one.';

/// BR-2: approves [request]; the caller sets [category]'s price to
/// `newPrice` in the same transaction.
PriceRequest approvePriceRequest(
  PriceRequest request, {
  required BedCategory category,
  required UserAccount by,
  required DateTime at,
}) {
  requirePermission(by, Permission.decidePriceChange);
  _requireWaiting(request, deciding: true);
  final stale = staleError(request, category);
  if (stale != null) throw StalePriceRequest(stale);
  return request._with(
    decision: PriceDecision(
      kind: PriceDecisionKind.approved,
      note: null,
      decidedBy: by.id,
      decidedAt: at,
    ),
  );
}

/// BR-2: rejects [request]; [note] (the reason the supervisor sees) is
/// required.
PriceRequest rejectPriceRequest(
  PriceRequest request, {
  required UserAccount by,
  required String? note,
  required DateTime at,
}) {
  requirePermission(by, Permission.decidePriceChange);
  _requireWaiting(request, deciding: true);
  final reason = note?.trim() ?? '';
  if (reason.isEmpty) {
    throw const PriceRequestRuleViolation(
      'Give a reason for rejecting the price change.',
    );
  }
  return request._with(
    decision: PriceDecision(
      kind: PriceDecisionKind.rejected,
      note: reason,
      decidedBy: by.id,
      decidedAt: at,
    ),
  );
}

/// `+50`, `−50`: a price change a night, without KES.
String formatPriceChange(int change) =>
    '${change < 0 ? '−' : '+'}${formatKesPlain(change.abs())}';
