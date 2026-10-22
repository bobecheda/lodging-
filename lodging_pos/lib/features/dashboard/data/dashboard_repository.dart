import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import '../../payments/domain/payment_rules.dart';
import '../domain/dashboard.dart';

/// Reads what the owner's Today needs; the figures themselves are worked
/// out in `domain/dashboard.dart`.
class DashboardRepository {
  DashboardRepository(this._db);

  final AppDatabase _db;

  /// Fires when anything the cards read changes.
  Stream<void> changes() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.payments,
          _db.refunds,
          _db.refundDecisions,
          _db.voids,
          _db.stays,
          _db.stayCharges,
          _db.priceRequests,
          _db.priceDecisions,
        ]),
      )
      .map((_) {});

  /// Payments received and refunds paid out at or after [from], with their
  /// voids marked.
  Future<List<MoneyMove>> moneyMoves(DateTime from) async {
    final voided = await _voided();
    final payments = await (_db.select(
      _db.payments,
    )..where((p) => p.receivedAt.isBiggerOrEqualValue(from))).get();
    final payouts =
        await (_db.select(_db.refunds)..where(
              (r) => r.paidAt.isNotNull() & r.paidAt.isBiggerOrEqualValue(from),
            ))
            .get();
    return [
      for (final p in payments)
        MoneyMove(
          at: p.receivedAt,
          amount: p.amount,
          method: PaymentMethod.parse(p.method),
          isPayout: false,
          voided: voided.contains(('payment', p.id)),
        ),
      for (final r in payouts)
        MoneyMove(
          at: r.paidAt!,
          amount: r.amount,
          method: PaymentMethod.parse(r.method!),
          isPayout: true,
          voided: voided.contains(('refund', r.id)),
        ),
    ];
  }

  /// Every stay with a night ending at or after [from], for occupancy: its
  /// charges, whether it was voided, and the nights of a refund that wasn't
  /// rejected.
  Future<List<StayNights>> stayNights(DateTime from) async {
    final voided = await _voided();
    final charges = await (_db.select(
      _db.stayCharges,
    )..where((c) => c.periodEnd.isBiggerOrEqualValue(from))).get();
    final stayIds = {for (final c in charges) c.stayId};
    // All of those stays' charges (an earlier one may end before [from]).
    final all = await (_db.select(
      _db.stayCharges,
    )..where((c) => c.stayId.isIn(stayIds))).get();
    final refunds = await (_db.select(
      _db.refunds,
    )..where((r) => r.stayId.isIn(stayIds))).get();
    final rejected = {
      for (final d in await (_db.select(
        _db.refundDecisions,
      )..where((d) => d.decision.equals('rejected'))).get())
        d.refundId,
    };
    final refundedNights = {
      for (final r in refunds)
        if (!rejected.contains(r.id)) r.stayId: r.nights,
    };
    final byStay = <String, List<ChargeNights>>{};
    for (final c in all) {
      byStay
          .putIfAbsent(c.stayId, () => [])
          .add(ChargeNights(nights: c.nights, periodEnd: c.periodEnd));
    }
    return [
      for (final MapEntry(key: stayId, value: list) in byStay.entries)
        StayNights(
          charges: list,
          voided: voided.contains(('stay', stayId)),
          refundedNights: refundedNights[stayId] ?? 0,
        ),
    ];
  }

  /// Refunds waiting for the owner's decision (BR-8a), oldest first.
  Future<List<RefundAwaiting>> refundsAwaiting() async {
    final decided = _db.selectOnly(_db.refundDecisions)
      ..addColumns([_db.refundDecisions.refundId]);
    final requester = _db.alias(_db.users, 'requester');
    final rows =
        await (_db.select(_db.refunds).join([
                innerJoin(
                  _db.stays,
                  _db.stays.id.equalsExp(_db.refunds.stayId),
                ),
                innerJoin(
                  _db.guests,
                  _db.guests.id.equalsExp(_db.stays.guestId),
                ),
                innerJoin(
                  requester,
                  requester.id.equalsExp(_db.refunds.requestedBy),
                ),
              ])
              ..where(_db.refunds.id.isNotInQuery(decided))
              ..orderBy([OrderingTerm.asc(_db.refunds.requestedAt)]))
            .get();
    return [
      for (final row in rows)
        RefundAwaiting(
          refundId: row.readTable(_db.refunds).id,
          guestName: row.readTable(_db.guests).fullName,
          roomNumber: row.readTable(_db.stays).roomNumber,
          bedLabel: row.readTable(_db.stays).bedLabel,
          nights: row.readTable(_db.refunds).nights,
          amount: row.readTable(_db.refunds).amount,
          requestedBy: row.readTable(requester).fullName,
          requestedAt: row.readTable(_db.refunds).requestedAt,
        ),
    ];
  }

  /// Price requests waiting for the owner (BR-2): not withdrawn, not
  /// decided; oldest first.
  Future<List<PriceAwaiting>> pricesAwaiting() async {
    final decided = _db.selectOnly(_db.priceDecisions)
      ..addColumns([_db.priceDecisions.requestId]);
    final rows =
        await (_db.select(_db.priceRequests).join([
                innerJoin(
                  _db.bedCategories,
                  _db.bedCategories.id.equalsExp(_db.priceRequests.categoryId),
                ),
                innerJoin(
                  _db.users,
                  _db.users.id.equalsExp(_db.priceRequests.requestedBy),
                ),
              ])
              ..where(
                _db.priceRequests.withdrawnAt.isNull() &
                    _db.priceRequests.id.isNotInQuery(decided),
              )
              ..orderBy([OrderingTerm.asc(_db.priceRequests.requestedAt)]))
            .get();
    return [
      for (final row in rows)
        PriceAwaiting(
          requestId: row.readTable(_db.priceRequests).id,
          categoryName: row.readTable(_db.bedCategories).name,
          oldPrice: row.readTable(_db.priceRequests).oldPrice,
          newPrice: row.readTable(_db.priceRequests).newPrice,
          requestedBy: row.readTable(_db.users).fullName,
          requestedByRole: row.readTable(_db.users).role,
          requestedAt: row.readTable(_db.priceRequests).requestedAt,
        ),
    ];
  }

  /// (target_type, target_id) of every void.
  Future<Set<(String, String)>> _voided() async => {
    for (final v in await _db.select(_db.voids).get())
      (v.targetType, v.targetId),
  };
}
