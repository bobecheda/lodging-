import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../setup/domain/rooms.dart';
import '../domain/housekeeping.dart';

/// A bed's open cleaning task.
final class OpenTask {
  const OpenTask({
    required this.id,
    required this.housekeeperId,
    required this.housekeeperName,
    required this.assignedAt,
  });

  final String id;
  final String housekeeperId;

  /// First name, or full name when shared ([housekeeperNames]).
  final String housekeeperName;

  /// UTC.
  final DateTime assignedAt;
}

/// A bed as the cleaning panel shows it.
final class BedCleaning {
  const BedCleaning({
    required this.bedId,
    required this.roomNumber,
    required this.label,
    required this.categoryName,
    required this.cleanliness,
    required this.openTask,
    required this.lastCheckoutAt,
  });

  final String bedId;
  final String roomNumber;
  final BedLabel label;
  final String categoryName;
  final Cleanliness cleanliness;
  final OpenTask? openTask;

  /// UTC; the bed's latest checkout, if it has had a guest.
  final DateTime? lastCheckoutAt;
}

/// A housekeeping action can't be done now; [message] says why.
class HousekeepingRefused implements Exception {
  const HousekeepingRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Open tasks: neither completed nor cancelled.
Expression<bool> _open($HousekeepingTasksTable t) =>
    t.completedAt.isNull() & t.cancelledAt.isNull();

/// Cancels the open cleaning tasks of [bedIds] (`housekeeping.cancel`),
/// when their bed or room is closed (AD-2). The beds stay not cleaned: a
/// cancelled task never makes a bed clean. Call inside the closing write.
Future<void> cancelOpenCleaning(
  AppDatabase db,
  AuditedWrites w,
  Iterable<String> bedIds,
  String userId,
) async {
  final open = await (db.select(
    db.housekeepingTasks,
  )..where((t) => t.bedId.isIn(bedIds) & _open(t))).get();
  for (final task in open) {
    await w.update(
      db.housekeepingTasks,
      task.id,
      HousekeepingTasksCompanion(
        cancelledAt: Value(w.now),
        cancelledBy: Value(userId),
      ),
      action: 'housekeeping.cancel',
    );
  }
}

/// Housekeeping (FD-9). Each change is one writeWithAudit and checks again
/// inside it; none needs a shift (no money moves).
class HousekeepingRepository {
  HousekeepingRepository(this._db, this._audit);

  final AppDatabase _db;
  final AuditWriter _audit;

  /// Active housekeepers by name, for the dropdown.
  Stream<List<HousekeeperOption>> watchHousekeepers() =>
      (_db.select(_db.housekeepers)
            ..where((h) => h.isActive.equals(true))
            ..orderBy([(h) => OrderingTerm.asc(h.fullName)]))
          .watch()
          .map(
            (rows) => [for (final h in rows) (id: h.id, fullName: h.fullName)],
          );

  /// [bedId] for the cleaning panel, watched.
  Stream<BedCleaning> watchBed(String bedId) {
    final query = _db.select(_db.beds).join([
      innerJoin(_db.rooms, _db.rooms.id.equalsExp(_db.beds.roomId)),
      innerJoin(
        _db.bedCategories,
        _db.bedCategories.id.equalsExp(_db.beds.categoryId),
      ),
      leftOuterJoin(
        _db.housekeepingTasks,
        _db.housekeepingTasks.bedId.equalsExp(_db.beds.id) &
            _open(_db.housekeepingTasks),
      ),
    ])..where(_db.beds.id.equals(bedId));
    return query.watchSingle().asyncMap((row) async {
      final bed = row.readTable(_db.beds);
      final task = row.readTableOrNull(_db.housekeepingTasks);
      final lastCheckout =
          await (_db.selectOnly(_db.stays)
                ..addColumns([_db.stays.checkedOutAt.max()])
                ..where(_db.stays.bedId.equals(bedId)))
              .map((r) => r.read(_db.stays.checkedOutAt.max()))
              .getSingle();
      return BedCleaning(
        bedId: bed.id,
        roomNumber: row.readTable(_db.rooms).roomNumber,
        label: BedLabel.parse(bed.label),
        categoryName: row.readTable(_db.bedCategories).name,
        cleanliness: Cleanliness.parse(bed.cleanliness),
        openTask: task == null
            ? null
            : OpenTask(
                id: task.id,
                housekeeperId: task.housekeeperId,
                housekeeperName:
                    (await names())[task.housekeeperId] ??
                    await _fullName(task.housekeeperId),
                assignedAt: task.assignedAt,
              ),
        lastCheckoutAt: lastCheckout,
      );
    });
  }

  /// Every active housekeeper's display name ([activeHousekeeperNames]).
  Future<Map<String, String>> names() => activeHousekeeperNames(_db);

  Future<String> _fullName(String housekeeperId) async => (await (_db.select(
    _db.housekeepers,
  )..where((h) => h.id.equals(housekeeperId))).getSingle()).fullName;

  /// Gives [bedId] to [housekeeperId] (`housekeeping.assign`).
  Future<void> assign(
    UserAccount user,
    String bedId,
    String housekeeperId,
  ) async {
    requirePermission(user, Permission.assignHousekeeping);
    await _audit.writeWithAudit(
      action: 'housekeeping.assign',
      userId: user.id,
      body: (w) async {
        await _checkAssignable(bedId, housekeeperId);
        await _newTask(w, bedId, housekeeperId, user.id);
      },
    );
  }

  /// "Already cleaned · mark clean": a task created and completed in one
  /// operation (`housekeeping.assign` + `bed.mark_clean`), so BR-9 holds.
  Future<void> cleanNow(
    UserAccount user,
    String bedId,
    String housekeeperId,
  ) async {
    requirePermission(user, Permission.assignHousekeeping);
    requirePermission(user, Permission.markClean);
    await _audit.writeWithAudit(
      action: 'bed.mark_clean',
      userId: user.id,
      body: (w) async {
        await _checkAssignable(bedId, housekeeperId);
        final task = await _newTask(w, bedId, housekeeperId, user.id);
        await _complete(w, task.id, bedId, user.id);
      },
    );
  }

  /// Completes [bedId]'s open task: the bed is clean (`bed.mark_clean`).
  Future<void> markClean(UserAccount user, String bedId) async {
    requirePermission(user, Permission.markClean);
    await _audit.writeWithAudit(
      action: 'bed.mark_clean',
      userId: user.id,
      body: (w) async {
        final task = await _openTask(bedId);
        if (task == null) {
          throw const HousekeepingRefused(
            'Nobody has been given this bed. Assign the cleaning first.',
          );
        }
        await _complete(w, task.id, bedId, user.id);
      },
    );
  }

  /// Gives [bedId]'s open task to [housekeeperId] instead
  /// (`housekeeping.reassign`; the audit keeps the old and new one).
  Future<void> reassign(
    UserAccount user,
    String bedId,
    String housekeeperId,
  ) async {
    requirePermission(user, Permission.assignHousekeeping);
    await _audit.writeWithAudit(
      action: 'housekeeping.reassign',
      userId: user.id,
      body: (w) async {
        final task = await _openTask(bedId);
        if (task == null) {
          throw const HousekeepingRefused(
            'This bed has no cleaning to reassign. Assign it instead.',
          );
        }
        if (task.housekeeperId == housekeeperId) {
          throw const HousekeepingRefused('Choose a different housekeeper.');
        }
        if (!await _isActive(housekeeperId)) {
          throw const HousekeepingRefused(
            'That housekeeper is no longer active. Choose another.',
          );
        }
        await w.update(
          _db.housekeepingTasks,
          task.id,
          HousekeepingTasksCompanion(housekeeperId: Value(housekeeperId)),
        );
      },
    );
  }

  Future<void> _checkAssignable(String bedId, String housekeeperId) async {
    final bed = await (_db.select(
      _db.beds,
    )..where((b) => b.id.equals(bedId))).getSingle();
    final problem = assignBlocker(
      cleanliness: Cleanliness.parse(bed.cleanliness),
      hasOpenTask: await _openTask(bedId) != null,
      housekeeperActive: await _isActive(housekeeperId),
    );
    if (problem != null) throw HousekeepingRefused(problem);
  }

  Future<HousekeepingTaskRow> _newTask(
    AuditedWrites w,
    String bedId,
    String housekeeperId,
    String userId,
  ) => w.insert(
    _db.housekeepingTasks,
    HousekeepingTasksCompanion.insert(
      bedId: bedId,
      housekeeperId: housekeeperId,
      assignedBy: userId,
      assignedAt: w.now,
    ),
    action: 'housekeeping.assign',
  );

  Future<void> _complete(
    AuditedWrites w,
    String taskId,
    String bedId,
    String userId,
  ) async {
    await w.update(
      _db.housekeepingTasks,
      taskId,
      HousekeepingTasksCompanion(
        completedAt: Value(w.now),
        completedBy: Value(userId),
      ),
      action: 'bed.mark_clean',
    );
    // BR-9: the only way a bed becomes clean.
    await w.update(
      _db.beds,
      bedId,
      const BedsCompanion(cleanliness: Value('clean')),
      action: 'bed.mark_clean',
    );
  }

  Future<HousekeepingTaskRow?> _openTask(String bedId) => (_db.select(
    _db.housekeepingTasks,
  )..where((t) => t.bedId.equals(bedId) & _open(t))).getSingleOrNull();

  Future<bool> _isActive(String housekeeperId) async =>
      (await (_db.select(
            _db.housekeepers,
          )..where((h) => h.id.equals(housekeeperId))).getSingleOrNull())
          ?.isActive ??
      false;
}

/// How many beds [housekeeperId] still has to clean (open tasks).
Future<int> openTaskCount(AppDatabase db, String housekeeperId) async =>
    (await (db.select(db.housekeepingTasks)
              ..where((t) => t.housekeeperId.equals(housekeeperId) & _open(t)))
            .get())
        .length;

/// Every active housekeeper's display name: first names, full names when
/// shared ([housekeeperNames]).
Future<Map<String, String>> activeHousekeeperNames(AppDatabase db) async =>
    housekeeperNames([
      for (final h in await (db.select(
        db.housekeepers,
      )..where((h) => h.isActive.equals(true))).get())
        (id: h.id, fullName: h.fullName),
    ]);
