import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../domain/void_rules.dart';

/// A void as recorded: why, by whom, when.
final class VoidRecord {
  const VoidRecord({
    required this.reason,
    required this.voidedBy,
    required this.voidedAt,
  });

  final String reason;

  /// The voider's full name.
  final String voidedBy;

  /// UTC.
  final DateTime voidedAt;
}

/// What the Voids screen shows for one payment's receipt: the two voids it
/// offers and any void already recorded.
final class VoidView {
  const VoidView({
    required this.paymentId,
    required this.paymentPlan,
    required this.stayPlan,
    this.paymentVoid,
    this.stayVoid,
  });

  final String paymentId;

  /// Voiding this payment alone.
  final VoidPlan paymentPlan;

  /// Voiding the stay it paid for (with both beds when it paid both).
  final VoidPlan stayPlan;
  final VoidRecord? paymentVoid;
  final VoidRecord? stayVoid;
}

/// Voids (AD-7, BR-11) on the desk, the only place they are written: each
/// through writeWithAudit as `void.create`, pushed like any desk row. The
/// rules are `domain/void_rules.dart`; the cloud checks the same ones when
/// the row arrives (`supabase/migrations/…_voids.sql`).
class VoidsRepository {
  VoidsRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditWriter _audit;

  /// The receipt [paymentId] as the Voids screen shows it, watched: a void
  /// (here or in another window) shows at once.
  Stream<VoidView> watchView(String paymentId) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {_db.voids, _db.stays, _db.payments, _db.refunds},
      )
      .watch()
      .asyncMap((_) => view(paymentId));

  Future<VoidView> view(String paymentId) async {
    final facts = await _facts(paymentIds: {paymentId});
    final payment = facts.payments[paymentId]!;
    final records = await _records({
      ...facts.payments.keys,
      ...facts.stays.keys,
    });
    VoidRecord? recordOf(String type, String id) => records[(type, id)];
    final stayId = payment.stayIds.first;
    return VoidView(
      paymentId: paymentId,
      paymentPlan: paymentVoidPlan(facts, paymentId),
      stayPlan: stayVoidPlan(facts, stayId),
      paymentVoid: recordOf('payment', paymentId),
      stayVoid: payment.stayIds
          .map((id) => recordOf('stay', id))
          .whereType<VoidRecord>()
          .firstOrNull,
    );
  }

  /// Voids [paymentId] alone. Throws [NotPermitted] or [VoidRuleViolation].
  Future<void> voidPayment(UserAccount user, String paymentId, String reason) =>
      _write(
        user,
        reason,
        (facts) => paymentVoidPlan(facts, paymentId),
        paymentIds: {paymentId},
      );

  /// Voids [stayId] with every payment still behind it, and the other bed's
  /// stay when one payment paid both; active stays close and their beds
  /// need cleaning. Throws [NotPermitted] or [VoidRuleViolation].
  Future<void> voidStay(UserAccount user, String stayId, String reason) =>
      _write(
        user,
        reason,
        (facts) => stayVoidPlan(facts, stayId),
        stayIds: {stayId},
      );

  Future<void> _write(
    UserAccount user,
    String reason,
    VoidPlan Function(VoidFacts) planOf, {
    Set<String> paymentIds = const {},
    Set<String> stayIds = const {},
  }) => _audit.writeWithAudit(
    action: 'void.create',
    userId: user.id,
    body: (w) async {
      // Read again inside the transaction: what the screen showed may have
      // changed (another void, a checkout).
      final plan = planOf(
        await _facts(paymentIds: paymentIds, stayIds: stayIds),
      );
      checkVoid(plan, by: user, reason: reason);
      final why = cleanVoidReason(reason);
      Future<void> voidRow(VoidTarget target, String id) => w.insert(
        _db.voids,
        VoidsCompanion.insert(
          targetType: target.code,
          targetId: id,
          reason: why,
          voidedBy: user.id,
          voidedAt: w.now,
        ),
      );
      for (final s in plan.stays) {
        await voidRow(VoidTarget.stay, s.id);
      }
      for (final p in plan.payments) {
        await voidRow(VoidTarget.payment, p.id);
      }
      for (final s in plan.staysToClose) {
        final row = await (_db.select(
          _db.stays,
        )..where((r) => r.id.equals(s.id))).getSingle();
        await w.update(
          _db.stays,
          s.id,
          StaysCompanion(
            status: const Value('closed'),
            checkedOutAt: Value(w.now),
            checkedOutBy: Value(user.id),
          ),
        );
        // As at checkout (BR-9): only a finished cleaning makes it clean.
        await w.update(
          _db.beds,
          row.bedId,
          const BedsCompanion(cleanliness: Value('not_cleaned')),
        );
      }
    },
  );

  /// Every payment and stay tied to [paymentIds] and [stayIds] through
  /// their charges, with who made them, refunds and voids.
  Future<VoidFacts> _facts({
    Set<String> paymentIds = const {},
    Set<String> stayIds = const {},
  }) async {
    final payments = {...paymentIds};
    final stays = {...stayIds};
    final charges = <StayChargeRow>{};
    while (true) {
      final found = await (_db.select(
        _db.stayCharges,
      )..where((c) => c.paymentId.isIn(payments) | c.stayId.isIn(stays))).get();
      final before = (payments.length, stays.length);
      for (final c in found) {
        charges.add(c);
        payments.add(c.paymentId);
        stays.add(c.stayId);
      }
      if ((payments.length, stays.length) == before) break;
    }
    final voided = {
      for (final v in await (_db.select(
        _db.voids,
      )..where((v) => v.targetId.isIn({...payments, ...stays}))).get())
        (v.targetType, v.targetId),
    };
    final refunded = {
      for (final r in await (_db.select(
        _db.refunds,
      )..where((r) => r.stayId.isIn(stays))).get())
        r.stayId,
    };
    final paymentRows = await (_db.select(
      _db.payments,
    )..where((p) => p.id.isIn(payments))).get();
    final stayRows = await (_db.select(
      _db.stays,
    )..where((s) => s.id.isIn(stays))).get();
    List<String> ids(Iterable<String> all) => all.toSet().toList();
    return VoidFacts(
      payments: [
        for (final p in paymentRows)
          VoidPayment(
            id: p.id,
            receiptNumber: p.receiptNumber,
            amount: p.amount,
            receivedBy: p.receivedBy,
            stayIds: ids([
              for (final c in charges)
                if (c.paymentId == p.id) c.stayId,
            ]),
            voided: voided.contains(('payment', p.id)),
          ),
      ],
      stays: [
        for (final s in stayRows)
          VoidStay(
            id: s.id,
            roomNumber: s.roomNumber,
            bedLabel: s.bedLabel,
            checkedInBy: s.checkedInBy,
            isActive: s.status == 'active',
            paymentIds: ids([
              for (final c in charges)
                if (c.stayId == s.id) c.paymentId,
            ]),
            hasRefund: refunded.contains(s.id),
            voided: voided.contains(('stay', s.id)),
          ),
      ],
    );
  }

  Future<Map<(String, String), VoidRecord>> _records(Set<String> ids) async {
    final names = {
      for (final u in await _db.select(_db.users).get()) u.id: u.fullName,
    };
    return {
      for (final v in await (_db.select(
        _db.voids,
      )..where((v) => v.targetId.isIn(ids))).get())
        (v.targetType, v.targetId): VoidRecord(
          reason: v.reason,
          voidedBy: names[v.voidedBy] ?? '',
          voidedAt: v.voidedAt,
        ),
    };
  }
}
