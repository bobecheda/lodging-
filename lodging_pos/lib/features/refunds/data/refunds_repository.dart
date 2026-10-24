import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../../core/sync/cloud_writes.dart';
import '../../payments/data/payment_writes.dart';
import '../../payments/domain/payment_rules.dart';
import '../../setup/domain/prices_settings.dart';
import '../../shifts/domain/shift.dart';
import '../../shifts/domain/shift_rules.dart';
import '../domain/refund.dart';
import '../domain/refund_detail.dart';

export '../domain/refund_detail.dart';

/// The desk's Refunds screen, newest first in each part.
final class DeskRefunds {
  const DeskRefunds({
    required this.toPay,
    required this.waiting,
    required this.rejected,
  });

  /// Approved, not yet paid.
  final List<RefundView> toPay;

  /// Requested, waiting for the owner.
  final List<RefundView> waiting;

  /// Rejected in the last [rejectedShownFor].
  final List<RefundView> rejected;

  static const rejectedShownFor = Duration(days: 14);
}

/// A payout the pay panel asks for.
final class PayoutRequest {
  const PayoutRequest({
    required this.refundId,
    required this.method,
    this.mpesaCode,
    this.sendTo,
  });

  final String refundId;
  final PaymentMethod? method;
  final String? mpesaCode;

  /// The phone an M-Pesa payout goes to.
  final String? sendTo;
}

/// The payout couldn't be saved; [message] says why.
final class PayoutRefused implements Exception {
  const PayoutRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Refund decisions (the owner) and payouts (the desk), AD-7. The rules are
/// in `domain/refund.dart`; every write re-checks them inside its
/// transaction, and the database's triggers check them again.
class RefundsRepository {
  RefundsRepository(this._db, this._audit, {this._cloud});

  final AppDatabase _db;
  final AuditWriter _audit;

  /// Once this desk is connected, decisions go to the cloud first.
  final CloudWrites? _cloud;

  /// Fires when a refund, decision or payout changes.
  Stream<void> changes() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([_db.refunds, _db.refundDecisions]),
      )
      .map((_) {});

  // ── Reading ────────────────────────────────────────────────────────────

  Future<RefundView> view(String refundId) async =>
      (await _views(where: _db.refunds.id.equals(refundId))).single;

  /// The owner's detail for [refundId].
  Future<RefundDetail> detail(String refundId) async {
    final v = await view(refundId);
    final stay = await (_db.select(
      _db.stays,
    )..where((s) => s.id.equals(v.refund.stayId))).getSingle();
    final rows =
        await (_db.select(_db.stayCharges).join([
                innerJoin(
                  _db.payments,
                  _db.payments.id.equalsExp(_db.stayCharges.paymentId),
                ),
              ])
              ..where(_db.stayCharges.stayId.equals(stay.id))
              ..orderBy([OrderingTerm.asc(_db.stayCharges.periodStart)]))
            .get();
    final charges = [for (final r in rows) r.readTable(_db.stayCharges)];
    return RefundDetail(
      view: v,
      categoryName: charges.first.categoryName,
      checkInAt: stay.checkInAt,
      checkedOutAt: stay.checkedOutAt!,
      charges: [
        for (final r in rows)
          PaidCharge(
            nights: r.readTable(_db.stayCharges).nights,
            pricePerNight: r.readTable(_db.stayCharges).pricePerNight,
            receiptNumber: r.readTable(_db.payments).receiptNumber,
          ),
      ],
    );
  }

  /// The desk's three lists at [now]: to pay, waiting, and rejected in the
  /// last 14 days.
  Future<DeskRefunds> deskRefunds(DateTime now) async {
    final all = await _views();
    final since = now.subtract(DeskRefunds.rejectedShownFor);
    List<RefundView> where(bool Function(RefundView v) test) => [
      for (final v in all)
        if (test(v)) v,
    ];
    return DeskRefunds(
      toPay: where((v) => v.status == RefundStatus.approved),
      waiting: where((v) => v.status == RefundStatus.requested),
      rejected: where(
        (v) =>
            v.status == RefundStatus.rejected &&
            v.refund.decision!.decidedAt.isAfter(since),
      ),
    );
  }

  Future<List<RefundView>> _views({Expression<bool>? where}) async {
    final requester = _db.alias(_db.users, 'requester');
    final decider = _db.alias(_db.users, 'decider');
    final payer = _db.alias(_db.users, 'payer');
    final query = _db.select(_db.refunds).join([
      innerJoin(_db.stays, _db.stays.id.equalsExp(_db.refunds.stayId)),
      innerJoin(_db.guests, _db.guests.id.equalsExp(_db.stays.guestId)),
      innerJoin(requester, requester.id.equalsExp(_db.refunds.requestedBy)),
      leftOuterJoin(
        _db.refundDecisions,
        _db.refundDecisions.refundId.equalsExp(_db.refunds.id),
      ),
      leftOuterJoin(
        decider,
        decider.id.equalsExp(_db.refundDecisions.decidedBy),
      ),
      leftOuterJoin(payer, payer.id.equalsExp(_db.refunds.paidBy)),
    ]);
    if (where != null) query.where(where);
    query.orderBy([OrderingTerm.desc(_db.refunds.requestedAt)]);
    return [
      for (final row in await query.get())
        _toView(
          row,
          requester: row.readTable(requester),
          decider: row.readTableOrNull(decider),
          payer: row.readTableOrNull(payer),
        ),
    ];
  }

  RefundView _toView(
    TypedResult row, {
    required UserRow requester,
    required UserRow? decider,
    required UserRow? payer,
  }) {
    final r = row.readTable(_db.refunds);
    final d = row.readTableOrNull(_db.refundDecisions);
    final stay = row.readTable(_db.stays);
    return RefundView(
      refund: toRefund(r, d),
      guestName: row.readTable(_db.guests).fullName,
      guestPhone: row.readTable(_db.guests).phone,
      roomNumber: stay.roomNumber,
      bedLabel: stay.bedLabel,
      requestedByName: requester.fullName,
      requestedByRole: Role.parse(requester.role),
      decidedByName: decider?.fullName,
      paidByName: payer?.fullName,
      receiptNumber: r.receiptNumber,
    );
  }

  /// The domain refund for a `refunds` row and its decision, if any.
  static Refund toRefund(RefundRow r, RefundDecisionRow? d) => Refund(
    id: r.id,
    stayId: r.stayId,
    nights: r.nights,
    pricePerNight: r.pricePerNight,
    amount: r.amount,
    requestedBy: r.requestedBy,
    requestedAt: r.requestedAt,
    decision: d == null
        ? null
        : RefundDecision(
            kind: RefundDecisionKind.parse(d.decision),
            note: d.note,
            decidedBy: d.decidedBy,
            decidedAt: d.decidedAt,
          ),
    payout: r.paidAt == null
        ? null
        : RefundPayout(
            method: PaymentMethod.parse(r.method!),
            mpesaCode: r.mpesaCode,
            shiftId: r.shiftId!,
            paidBy: r.paidBy!,
            paidAt: r.paidAt!,
            phone: r.payoutPhone,
          ),
  );

  Future<Refund> _refund(String refundId) async {
    final r = await (_db.select(
      _db.refunds,
    )..where((x) => x.id.equals(refundId))).getSingle();
    final d = await (_db.select(
      _db.refundDecisions,
    )..where((x) => x.refundId.equals(refundId))).getSingleOrNull();
    return toRefund(r, d);
  }

  // ── Deciding (the owner) ───────────────────────────────────────────────

  /// Approves (`refund.approve`) or, with a [note], rejects
  /// (`refund.reject`) [refundId]: once, never by its requester, never with
  /// a different amount. Throws [NotPermitted] or [RefundRuleViolation].
  ///
  /// Once this desk is connected the decision is written in the cloud
  /// first (the first decision anywhere wins), then here with the same id
  /// and time; offline it is refused. Throws [OwnerCloudSignInNeeded] when
  /// the owner's cloud sign-in is missing (the screen asks for it).
  Future<void> decide(
    UserAccount owner,
    String refundId, {
    required bool approve,
    String? note,
  }) async {
    requirePermission(owner, Permission.approveRefund);
    final id = const Uuid().v4();
    final at = _audit.now();
    Refund decide(Refund current) => approve
        ? approveRefund(current, by: owner, at: at)
        : rejectRefund(current, by: owner, note: note, at: at);
    final cloud = _cloud;
    final inCloud = cloud != null && cloud.active;
    if (inCloud) {
      // The rules first, so the cloud never gets a decision they refuse.
      final decision = decide(await _refund(refundId)).decision!;
      try {
        await cloud.decideRefund(
          id: id,
          refundId: refundId,
          approve: approve,
          note: decision.note,
          at: at,
        );
      } on OwnerCloudSignInNeeded {
        rethrow;
      } on CloudWriteRefused catch (e) {
        throw RefundRuleViolation(
          cloudRefusalMessage(
            e,
            needsInternet: approve
                ? 'Approving needs an internet connection.'
                : 'Rejecting needs an internet connection.',
          ),
        );
      }
    }
    try {
      await _audit.writeWithAudit(
        action: approve ? 'refund.approve' : 'refund.reject',
        userId: owner.id,
        inCloud: {if (inCloud) 'refund_decisions'},
        body: (w) async {
          final decision = decide(await _refund(refundId)).decision!;
          await w.insert(
            _db.refundDecisions,
            RefundDecisionsCompanion.insert(
              id: Value(id),
              refundId: refundId,
              decision: decision.kind.code,
              note: Value(decision.note),
              decidedBy: owner.id,
              decidedAt: decision.decidedAt,
            ),
          );
        },
      );
    } on RefundRuleViolation {
      rethrow;
    } on NotPermitted {
      rethrow;
    } catch (e) {
      // Another decision got in first (refund_decisions.refund_id is
      // UNIQUE): the first one wins.
      if ('$e'.contains('UNIQUE')) {
        throw const RefundRuleViolation(
          'This refund has already been decided.',
        );
      }
      rethrow;
    }
  }

  // ── Paying (the desk) ──────────────────────────────────────────────────

  /// Pays [request]'s approved refund from the user's own open shift
  /// (`refund.pay`): the amount as calculated, in full; the next receipt
  /// number from the shared counter. Returns the REFUND receipt's number.
  /// Throws [NotPermitted], [NoOpenShift], [RefundRuleViolation],
  /// [InvalidMpesaCode], [InvalidPayoutPhone] or [PayoutRefused].
  Future<String> pay(UserAccount user, PayoutRequest request) async {
    requirePermission(user, Permission.payRefund);
    final method = request.method;
    if (method == null) throw const PayoutRefused('Choose how it was paid.');
    return _audit.writeWithAudit(
      action: 'refund.pay',
      userId: user.id,
      body: (w) async {
        final row = await ownOpenShift(_db, w, user.id);
        final shift = row == null
            ? null
            : OpenShift(
                id: row.id,
                userId: row.userId,
                userName: user.fullName,
                openedAt: row.openedAt,
                openingFloat: row.openingFloat,
              );
        final code = method == PaymentMethod.paybill
            ? normalizeMpesaCode(request.mpesaCode ?? '')
            : request.mpesaCode;
        final usedOn = code == null || code.isEmpty
            ? null
            : await mpesaCodeUse(_db, code);
        final paid = payRefund(
          await _refund(request.refundId),
          by: user,
          shift: shift,
          method: method,
          mpesaCode: code,
          codeInUse: usedOn != null,
          codeUsedOn: usedOn,
          sendTo: request.sendTo,
          at: w.now,
        );
        final payout = paid.payout!;
        final settings = {
          for (final s in await _db.select(_db.settings).get()) s.key: s.value,
        };
        final prefix = SettingsInput.fromStored(settings).receiptPrefix;
        final number = await takeReceiptNumber(_db, w, prefix);
        await w.update(
          _db.refunds,
          request.refundId,
          RefundsCompanion(
            method: Value(payout.method.code),
            mpesaCode: Value(payout.mpesaCode),
            shiftId: Value(payout.shiftId),
            paidBy: Value(payout.paidBy),
            paidAt: Value(payout.paidAt),
            receiptNumber: Value(number),
            payoutPhone: Value(payout.phone),
          ),
        );
        return number;
      },
    );
  }

  /// The refund whose REFUND receipt is [receiptNumber]'s, or null.
  Future<String?> refundIdForReceipt(String receiptNumber) async =>
      (await (_db.select(_db.refunds)
                ..where((r) => r.receiptNumber.equals(receiptNumber)))
              .getSingleOrNull())
          ?.id;
}
