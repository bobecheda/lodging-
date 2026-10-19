import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../payments/domain/payment_rules.dart';
import '../domain/shift.dart';
import '../domain/shift_close.dart';
import '../domain/shift_rules.dart';

/// A shift is already open on this device (at most one; see the
/// `shifts_one_open_per_device` index).
class ShiftAlreadyOpen implements Exception {
  const ShiftAlreadyOpen(this.shift);
  final OpenShift shift;

  @override
  String toString() => 'A shift is already open by ${shift.userName}';
}

/// A shift can't be closed now, or the count or note isn't right;
/// [message] says why.
class ShiftCloseRefused implements Exception {
  const ShiftCloseRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A shift as the owner's Shifts screen lists it.
final class ShiftSummary {
  const ShiftSummary({
    required this.id,
    required this.userId,
    required this.userName,
    required this.openedAt,
    required this.openingFloat,
    required this.closedAt,
    required this.takings,
    required this.expectedCash,
    required this.expectedPaybill,
    required this.firstCount,
    required this.counted,
    required this.variance,
    required this.note,
    required this.closedByName,
  });

  final String id;
  final String userId;
  final String userName;

  /// UTC.
  final DateTime openedAt;
  final int openingFloat;

  /// UTC; null while open.
  final DateTime? closedAt;

  /// Received so far (payments, voided ones excluded), for the 1% rule.
  final int takings;

  // Set once closed.
  final int? expectedCash;
  final int? expectedPaybill;
  final int? firstCount;
  final int? counted;
  final int? variance;
  final String? note;
  final String? closedByName;

  bool get isOpen => closedAt == null;
}

class ShiftRepository {
  ShiftRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditWriter _audit;

  Future<OpenShift?> openShiftOnThisDevice() async {
    final deviceId = await _db.deviceId();
    final query =
        _db.select(_db.shifts).join([
          innerJoin(_db.users, _db.users.id.equalsExp(_db.shifts.userId)),
        ])..where(
          _db.shifts.status.equals('open') &
              _db.shifts.deviceId.equals(deviceId),
        );
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return _toOpenShift(row.readTable(_db.shifts), row.readTable(_db.users));
  }

  /// Opens a shift for [user] with [openingFloat] whole KES (`shift.open`).
  Future<OpenShift> openShift({
    required UserAccount user,
    required int openingFloat,
  }) async {
    final problem = openingFloatError(openingFloat);
    if (problem != null) throw ArgumentError(problem);
    final row = await _audit.writeWithAudit(
      action: 'shift.open',
      userId: user.id,
      body: (w) async {
        final existing = await openShiftOnThisDevice();
        if (existing != null) throw ShiftAlreadyOpen(existing);
        return w.insert(
          _db.shifts,
          ShiftsCompanion.insert(
            userId: user.id,
            openedAt: w.now,
            openingFloat: openingFloat,
            status: 'open',
          ),
        );
      },
    );
    return OpenShift(
      id: row.id,
      userId: user.id,
      userName: user.fullName,
      openedAt: row.openedAt,
      openingFloat: row.openingFloat,
    );
  }

  /// What [shiftId] has taken so far: payments received and refunds paid
  /// out in it, voided ones excluded.
  Future<ShiftTakings> takings(String shiftId) async {
    final payments = await (_db.select(
      _db.payments,
    )..where((p) => p.shiftId.equals(shiftId))).get();
    // Only paid refunds carry the shift that paid them.
    final payouts = await (_db.select(
      _db.refunds,
    )..where((r) => r.shiftId.equals(shiftId))).get();
    final voids =
        await (_db.select(_db.voids)..where(
              (v) => v.targetId.isIn([
                for (final p in payments) p.id,
                for (final r in payouts) r.id,
              ]),
            ))
            .get();
    Set<String> voided(String type) => {
      for (final v in voids)
        if (v.targetType == type) v.targetId,
    };
    return takingsFrom(
      payments: [
        for (final p in payments)
          (id: p.id, amount: p.amount, method: PaymentMethod.parse(p.method)),
      ],
      refundPayouts: [
        for (final r in payouts)
          (id: r.id, amount: r.amount, method: PaymentMethod.parse(r.method!)),
      ],
      voidedPaymentIds: voided('payment'),
      voidedRefundIds: voided('refund'),
    );
  }

  /// Closes [shiftId] with a blind [firstCount] and the final [counted]
  /// cash (equal unless there was a recount) and [note] (`shift.close`).
  /// [shown] is what the review screen worked from: if a payment came in
  /// since, nothing is saved. Throws [NotPermitted] or [ShiftCloseRefused].
  Future<CloseFigures> closeShift(
    UserAccount user,
    String shiftId, {
    required int firstCount,
    required int counted,
    required String note,
    required ShiftTakings shown,
  }) async {
    return _audit.writeWithAudit(
      action: 'shift.close',
      userId: user.id,
      body: (w) async {
        final shift = await (_db.select(
          _db.shifts,
        )..where((s) => s.id.equals(shiftId))).getSingle();
        if (!mayCloseShift(user, shiftUserId: shift.userId)) {
          throw NotPermitted(
            shift.userId == user.id
                ? Permission.closeShift
                : Permission.closeOtherShifts,
          );
        }
        if (shift.status != 'open') {
          throw const ShiftCloseRefused('This shift is already closed.');
        }
        final countProblem = countError(firstCount) ?? countError(counted);
        if (countProblem != null) throw ShiftCloseRefused(countProblem);

        final now = await takings(shiftId);
        final change = closeChange(shown, now);
        if (change != null) throw ShiftCloseRefused(change);

        final figures = closeFigures(
          now,
          openingFloat: shift.openingFloat,
          firstCount: firstCount,
          counted: counted,
        );
        final noteProblem = closeNoteError(note, figures.variance);
        if (noteProblem != null) throw ShiftCloseRefused(noteProblem);

        await w.update(
          _db.shifts,
          shiftId,
          ShiftsCompanion(
            status: const Value('closed'),
            closedAt: Value(w.now),
            expectedCash: Value(figures.expectedCash),
            expectedPaybill: Value(figures.expectedPaybill),
            firstCount: Value(firstCount),
            countedCash: Value(counted),
            variance: Value(figures.variance),
            closeNote: Value(note.trim().isEmpty ? null : note.trim()),
            closedBy: Value(user.id),
          ),
        );
        return figures;
      },
    );
  }

  /// The newest [limit] shifts on this device, open ones included, for the
  /// owner's Shifts screen. Watched, so a close shows at once.
  Stream<List<ShiftSummary>> watchShifts({int limit = 50}) =>
      (_db.select(_db.shifts)
            ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
            ..limit(limit))
          .watch()
          .asyncMap((rows) async {
            final names = {
              for (final u in await _db.select(_db.users).get())
                u.id: u.fullName,
            };
            return [
              for (final s in rows)
                ShiftSummary(
                  id: s.id,
                  userId: s.userId,
                  userName: names[s.userId] ?? '',
                  openedAt: s.openedAt,
                  openingFloat: s.openingFloat,
                  closedAt: s.closedAt,
                  takings: (await takings(s.id)).received,
                  expectedCash: s.expectedCash,
                  expectedPaybill: s.expectedPaybill,
                  firstCount: s.firstCount,
                  counted: s.countedCash,
                  variance: s.variance,
                  note: s.closeNote,
                  closedByName: s.closedBy == null ? null : names[s.closedBy],
                ),
            ];
          });

  /// The shift with [id], as an open shift (for the close screen).
  Future<OpenShift?> openShiftById(String id) async {
    final row =
        await (_db.select(_db.shifts).join([
              innerJoin(_db.users, _db.users.id.equalsExp(_db.shifts.userId)),
            ])..where(
              _db.shifts.id.equals(id) & _db.shifts.status.equals('open'),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return _toOpenShift(row.readTable(_db.shifts), row.readTable(_db.users));
  }

  static OpenShift _toOpenShift(ShiftRow shift, UserRow user) => OpenShift(
    id: shift.id,
    userId: shift.userId,
    userName: user.fullName,
    openedAt: shift.openedAt,
    openingFloat: shift.openingFloat,
  );
}
