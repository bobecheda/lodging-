import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../domain/shift.dart';
import '../domain/shift_rules.dart';

/// A shift is already open on this device (at most one; see the
/// `shifts_one_open_per_device` index).
class ShiftAlreadyOpen implements Exception {
  const ShiftAlreadyOpen(this.shift);
  final OpenShift shift;

  @override
  String toString() => 'A shift is already open by ${shift.userName}';
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

  static OpenShift _toOpenShift(ShiftRow shift, UserRow user) => OpenShift(
    id: shift.id,
    userId: shift.userId,
    userName: user.fullName,
    openedAt: shift.openedAt,
    openingFloat: shift.openingFloat,
  );
}
