/// Voids (AD-7, BR-11): correcting a wrong payment or stay without hiding
/// it. A void says the money was never taken; it moves no money (money
/// handed back to a guest is a refund, BR-8). Pure Dart.
///
/// - Only users with [Permission.voidRecords] (the owner and the supervisor)
///   void, on the desk, and never a record they created themselves.
/// - A reason is required (at most [voidReasonMax] characters).
/// - Payments and stays are voided; a void itself can't be, and nothing is
///   voided twice (one void per target). Refund payouts aren't voided here
///   (the corrections book covers them).
/// - Voiding a stay voids every payment still standing behind it, and the
///   other bed's stay when one payment paid for both (BR-4): one booking.
///   Its active stays close; their beds become available and need
///   cleaning.
/// - A stay with a refund, and its payments, can't be voided.
library;

import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/money/kes.dart';

/// What a void row points at (`voids.target_type`). The table also allows
/// `refund` (a payout), which nothing writes yet.
enum VoidTarget {
  payment('payment'),
  stay('stay');

  const VoidTarget(this.code);
  final String code;
}

const voidReasonMax = 200;

/// The reason as stored.
String cleanVoidReason(String reason) => reason.trim();

/// Why [reason] can't be used, or null.
String? voidReasonError(String reason) {
  final r = cleanVoidReason(reason);
  if (r.isEmpty) return 'Say why it is being voided.';
  if (r.length > voidReasonMax) {
    return 'Keep the reason to $voidReasonMax characters.';
  }
  return null;
}

/// A void rule refused the action; [message] is shown to the user.
class VoidRuleViolation implements Exception {
  const VoidRuleViolation(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A payment as a void sees it.
final class VoidPayment {
  const VoidPayment({
    required this.id,
    required this.receiptNumber,
    required this.amount,
    required this.receivedBy,
    required this.stayIds,
    this.voided = false,
  });

  final String id;
  final String receiptNumber;

  /// Whole KES.
  final int amount;

  /// Who took it.
  final String receivedBy;

  /// The stays it paid for (two when one payment paid both beds).
  final List<String> stayIds;
  final bool voided;
}

/// A stay as a void sees it.
final class VoidStay {
  const VoidStay({
    required this.id,
    required this.roomNumber,
    required this.bedLabel,
    required this.checkedInBy,
    required this.isActive,
    required this.paymentIds,
    this.hasRefund = false,
    this.voided = false,
  });

  final String id;

  /// As let.
  final String roomNumber;
  final String bedLabel;
  final String checkedInBy;
  final bool isActive;

  /// Every payment behind its charges.
  final List<String> paymentIds;

  /// A refund was requested at its early checkout (any status).
  final bool hasRefund;
  final bool voided;

  /// `Room 4 · Bed A`.
  String get place => 'Room $roomNumber · Bed $bedLabel';
}

/// The payments and stays around one target, as read from the database.
final class VoidFacts {
  VoidFacts({
    required Iterable<VoidPayment> payments,
    required Iterable<VoidStay> stays,
  }) : payments = {for (final p in payments) p.id: p},
       stays = {for (final s in stays) s.id: s};

  final Map<String, VoidPayment> payments;
  final Map<String, VoidStay> stays;
}

/// What one void writes: a void row for each of [payments] and [stays],
/// all in one transaction.
final class VoidPlan {
  const VoidPlan._({
    required this.target,
    required this.targetId,
    required this.payments,
    required this.stays,
    required this.touched,
    required this.alreadyVoided,
  });

  final VoidTarget target;
  final String targetId;

  /// The payments it voids (none already voided).
  final List<VoidPayment> payments;

  /// The stays it voids: none for a payment void.
  final List<VoidStay> stays;

  /// Every stay the plan touches, for the rules: the voided ones, or the
  /// payment's own.
  final List<VoidStay> touched;

  /// The target was voided before.
  final String? alreadyVoided;

  /// Whole KES that leave the totals.
  int get amount => payments.fold(0, (sum, p) => sum + p.amount);

  /// Active stays this void closes (bed → available, not cleaned).
  List<VoidStay> get staysToClose => [
    for (final s in stays)
      if (s.isActive) s,
  ];

  /// After a payment void, the guests still in a bed with nights no money
  /// is behind (Today shows them).
  List<VoidStay> get staysLeftInUse => target == VoidTarget.payment
      ? [
          for (final s in touched)
            if (s.isActive && !s.voided) s,
        ]
      : const [];

  /// The confirmation's words.
  String get summary {
    final money = [
      for (final p in payments) '${p.receiptNumber} (${formatKes(p.amount)})',
    ];
    final what = [
      if (stays.isNotEmpty) _and([for (final s in stays) s.place]),
      if (money.isNotEmpty) _and(money),
    ];
    final closing = staysToClose;
    final inUse = staysLeftInUse;
    return [
      'Voids ${what.join(', and ')}.',
      if (closing.length == 1)
        '${closing.single.place} becomes available and needs cleaning.'
      else if (closing.length > 1)
        'Both beds become available and need cleaning.',
      if (inUse.isNotEmpty)
        '${_and([for (final s in inUse) s.place])} '
            '${inUse.length == 1 ? 'stays' : 'stay'} in use, with nights no '
            'money is behind. To correct a wrong method or M-Pesa code, void '
            'the stay instead, mark the bed clean and check the guest in '
            'again.',
    ].join(' ');
  }

  static String _and(List<String> items) => items.length <= 1
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

/// Voiding payment [paymentId] alone.
VoidPlan paymentVoidPlan(VoidFacts facts, String paymentId) {
  final p = facts.payments[paymentId]!;
  return VoidPlan._(
    target: VoidTarget.payment,
    targetId: paymentId,
    payments: p.voided ? const [] : [p],
    stays: const [],
    touched: [for (final id in p.stayIds) ?facts.stays[id]],
    alreadyVoided: p.voided
        ? '${p.receiptNumber} has already been voided.'
        : null,
  );
}

/// Voiding stay [stayId]: with every payment still standing behind it and
/// every stay those payments also paid for (one booking).
VoidPlan stayVoidPlan(VoidFacts facts, String stayId) {
  final start = facts.stays[stayId]!;
  if (start.voided) {
    return VoidPlan._(
      target: VoidTarget.stay,
      targetId: stayId,
      payments: const [],
      stays: const [],
      touched: [start],
      alreadyVoided: '${start.place} has already been voided.',
    );
  }
  final stays = <String>[];
  final payments = <String>[];
  final queue = [stayId];
  while (queue.isNotEmpty) {
    final s = facts.stays[queue.removeAt(0)];
    if (s == null || s.voided || stays.contains(s.id)) continue;
    stays.add(s.id);
    for (final pid in s.paymentIds) {
      final p = facts.payments[pid];
      // A voided payment no longer ties stays together.
      if (p == null || p.voided || payments.contains(pid)) continue;
      payments.add(pid);
      queue.addAll(p.stayIds);
    }
  }
  final voidStays = [for (final id in stays) facts.stays[id]!];
  return VoidPlan._(
    target: VoidTarget.stay,
    targetId: stayId,
    payments: [for (final id in payments) facts.payments[id]!],
    stays: voidStays,
    touched: voidStays,
    alreadyVoided: null,
  );
}

/// Why [by] can't carry out [plan] (the reason aside), or null. A screen
/// shows it instead of the button; [checkVoid] enforces it.
String? voidBlocker(VoidPlan plan, UserAccount by) {
  if (plan.alreadyVoided case final message?) return message;
  for (final s in plan.touched) {
    if (s.hasRefund) {
      return '${s.place} has a refund, so it can\'t be voided here. Write the '
          'correction in the corrections book.';
    }
  }
  final stayVoid = plan.target == VoidTarget.stay;
  for (final s in plan.stays) {
    if (s.checkedInBy == by.id) {
      return 'You checked ${s.place} in yourself, so someone else must void '
          'it.';
    }
  }
  for (final p in plan.payments) {
    if (p.receivedBy == by.id) {
      return 'You took ${p.receiptNumber} yourself, so someone else must void '
          '${stayVoid ? 'this stay' : 'it'}.';
    }
  }
  return null;
}

/// BR-11: [by] may carry out [plan] for [reason]. Throws [NotPermitted] or
/// [VoidRuleViolation].
void checkVoid(
  VoidPlan plan, {
  required UserAccount by,
  required String reason,
}) {
  requirePermission(by, Permission.voidRecords);
  if (voidBlocker(plan, by) case final message?) {
    throw VoidRuleViolation(message);
  }
  if (voidReasonError(reason) case final message?) {
    throw VoidRuleViolation(message);
  }
}
