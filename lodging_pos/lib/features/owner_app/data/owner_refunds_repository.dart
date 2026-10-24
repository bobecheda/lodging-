import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/auth/user_account.dart';
import '../../../core/clock/nairobi.dart';
import '../../payments/domain/payment_rules.dart';
import '../../refunds/domain/refund.dart';
import '../../refunds/domain/refund_detail.dart';
import 'owner_cloud.dart';
import 'owner_rows.dart';

/// A refund on the phone: the desk's [RefundDetail] (its `guestPhone` left
/// empty) and the guest's masked phone.
final class OwnerRefund {
  const OwnerRefund(this.detail, {required this.maskedPhone});
  final RefundDetail detail;
  final String maskedPhone;
}

/// The owner's refund decision from the phone (AD-7): the same rules as the
/// desk (`refunds/domain/refund.dart`), then `decide_refund` in the cloud,
/// first decision anywhere wins. The desk pulls it.
class OwnerRefundsRepository {
  OwnerRefundsRepository(this._cloud);

  final OwnerCloud _cloud;

  static const _refundColumns = [
    'id',
    'stay_id',
    'nights',
    'price_per_night',
    'amount',
    'requested_by',
    'requested_at',
    'method',
    'mpesa_code',
    'shift_id',
    'paid_by',
    'paid_at',
    'receipt_number',
  ];

  static const _decisionColumns = [
    'id',
    'refund_id',
    'decision',
    'note',
    'decided_by',
    'decided_at',
  ];

  /// The refund and its REFUND receipt's number, once paid.
  Future<(Refund, String?)> _refund(String refundId) async {
    final rows = await _cloud.rows(
      'refunds',
      _refundColumns,
      where: [Eq('id', refundId)],
    );
    if (rows.isEmpty) {
      throw const RefundRuleViolation('This refund isn’t in the cloud yet.');
    }
    final r = rows.single;
    final decisions = await _cloud.rows(
      'refund_decisions',
      _decisionColumns,
      where: [Eq('refund_id', refundId)],
    );
    final d = decisions.isEmpty ? null : decisions.single;
    final refund = Refund(
      id: r.str('id'),
      stayId: r.str('stay_id'),
      nights: r.integer('nights'),
      pricePerNight: r.integer('price_per_night'),
      amount: r.integer('amount'),
      requestedBy: r.str('requested_by'),
      requestedAt: r.time('requested_at'),
      decision: d == null
          ? null
          : RefundDecision(
              kind: RefundDecisionKind.parse(d.str('decision')),
              note: d.strOrNull('note'),
              decidedBy: d.str('decided_by'),
              decidedAt: d.time('decided_at'),
            ),
      payout: r.timeOrNull('paid_at') == null
          ? null
          : RefundPayout(
              method: PaymentMethod.parse(r.str('method')),
              mpesaCode: r.strOrNull('mpesa_code'),
              shiftId: r.str('shift_id'),
              paidBy: r.str('paid_by'),
              paidAt: r.time('paid_at'),
              phone: null,
            ),
    );
    return (refund, r.strOrNull('receipt_number'));
  }

  /// What the owner sees before deciding.
  Future<OwnerRefund> detail(String refundId) async {
    final (refund, receiptNumber) = await _refund(refundId);
    final users = await loadUsers(_cloud);
    final stay = (await _cloud.rows(
      'stays',
      [
        'id',
        'guest_id',
        'room_number',
        'bed_label',
        'check_in_at',
        'checked_out_at',
      ],
      where: [Eq('id', refund.stayId)],
    )).single;
    final guest = (await loadGuests(_cloud, [
      stay.str('guest_id'),
    ]))[stay.str('guest_id')];
    final charges = await _cloud.rows(
      'stay_charges',
      ['payment_id', 'nights', 'price_per_night', 'category_name'],
      where: [Eq('stay_id', refund.stayId)],
      orderBy: 'period_start',
    );
    final receipts = {
      for (final p in await _cloud.rows(
        'payments',
        ['id', 'receipt_number'],
        where: [
          InList('id', [for (final c in charges) c.str('payment_id')]),
        ],
      ))
        p.str('id'): p.str('receipt_number'),
    };
    final requester = users[refund.requestedBy];
    String? nameOf(String? id) => id == null ? null : users[id]?.name;
    return OwnerRefund(
      RefundDetail(
        view: RefundView(
          refund: refund,
          guestName: guest?.name ?? '—',
          guestPhone: '',
          roomNumber: stay.str('room_number'),
          bedLabel: stay.str('bed_label'),
          requestedByName: requester?.name ?? '—',
          requestedByRole: requester == null
              ? null
              : Role.parse(requester.role),
          decidedByName: nameOf(refund.decision?.decidedBy),
          paidByName: nameOf(refund.payout?.paidBy),
          receiptNumber: receiptNumber,
        ),
        categoryName: charges.isEmpty ? '' : charges.first.str('category_name'),
        checkInAt: stay.time('check_in_at'),
        checkedOutAt: stay.time('checked_out_at'),
        charges: [
          for (final c in charges)
            PaidCharge(
              nights: c.integer('nights'),
              pricePerNight: c.integer('price_per_night'),
              receiptNumber: receipts[c.str('payment_id')] ?? '—',
            ),
        ],
      ),
      maskedPhone: guest?.phoneMasked ?? '•••',
    );
  }

  /// Approves (`refund.approve`) or, with a [note], rejects
  /// (`refund.reject`) [refundId], stamped with the server's time. Throws
  /// [RefundRuleViolation] (with the cloud's answer when someone decided
  /// first), [OwnerCloudOffline] or [OwnerSignInRefused].
  Future<void> decide(
    UserAccount owner,
    String refundId, {
    required bool approve,
    String? note,
  }) async {
    final at = DateTime.parse(
      (await _cloud.rpc('server_time', const {}))! as String,
    ).toUtc();
    final (current, _) = await _refund(refundId);
    if (current.decision case final d?) {
      final users = await loadUsers(_cloud);
      throw RefundRuleViolation(
        _decidedBy(
          users[d.decidedBy]?.name,
          d.decidedAt,
          approved: d.kind == RefundDecisionKind.approved,
        ),
      );
    }
    // The rules first, so the cloud never gets a decision they refuse.
    final decision =
        (approve
                ? approveRefund(current, by: owner, at: at)
                : rejectRefund(current, by: owner, note: note, at: at))
            .decision!;
    final id = const Uuid().v4();
    final device = await _cloud.deviceId();
    final stamp = at.toIso8601String();
    final row = {
      'id': id,
      'created_at': stamp,
      'updated_at': stamp,
      'device_id': device,
      'refund_id': refundId,
      'decision': decision.kind.code,
      'note': decision.note,
      'decided_by': owner.id,
      'decided_at': stamp,
    };
    final answer = await _cloud.rpc('decide_refund', {
      'p_id': id,
      'p_refund_id': refundId,
      'p_decision': decision.kind.code,
      'p_note': decision.note,
      'p_at': stamp,
      'p_device_id': device,
      'p_audit': [
        {
          'id': const Uuid().v4(),
          'created_at': stamp,
          'updated_at': stamp,
          'device_id': device,
          'at': stamp,
          'operation_id': const Uuid().v4(),
          'user_id': owner.id,
          'action': approve ? 'refund.approve' : 'refund.reject',
          'entity': 'refund_decisions',
          'entity_id': id,
          'before_json': null,
          'after_json': jsonEncode(row),
        },
      ],
    });
    final reply = answer is Map ? answer : const {};
    switch (reply['status']) {
      case 'decided':
        return;
      case 'already_decided':
        final byName = reply['decided_by_name'] as String?;
        final when = DateTime.parse(reply['decided_at'] as String).toUtc();
        throw RefundRuleViolation(
          _decidedBy(byName, when, approved: reply['decision'] == 'approved'),
        );
      case 'missing':
        throw const RefundRuleViolation('This refund isn’t in the cloud yet.');
      default:
        throw const OwnerCloudRefused('The cloud gave an unexpected answer.');
    }
  }

  /// "Already decided by Grace Akinyi · Sat 24 Oct, 09:29 (approved)." (as
  /// the desk words it).
  static String _decidedBy(
    String? byName,
    DateTime at, {
    required bool approved,
  }) =>
      'Already decided by ${byName ?? 'someone else'} · '
      '${formatDayDateComma(at)} (${approved ? 'approved' : 'rejected'}).';
}
