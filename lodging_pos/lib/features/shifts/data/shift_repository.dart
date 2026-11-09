import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../../core/settings/setting_defaults.dart';
import '../../payments/domain/payment_rules.dart';
import '../domain/drawer.dart';
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

/// No count of the drawer yet: the supervisor or owner counts the starting
/// cash before the first shift (`drawer.start`).
class NoStartingCash implements Exception {
  const NoStartingCash();

  @override
  String toString() =>
      'The starting cash hasn’t been counted yet. Ask the supervisor or the '
      'owner to count it (Cash).';
}

/// A drawer count can't be saved; [message] says why.
class DrawerRefused implements Exception {
  const DrawerRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What a count at close did.
sealed class CountResult {
  const CountResult();
}

/// The count matched (first time or on the recount): the shift is closed.
final class CountClosed extends CountResult {
  const CountClosed(this.figures);
  final CloseFigures figures;
}

/// The first count didn't match; it's saved. Count once more.
final class CountAgain extends CountResult {
  const CountAgain();
}

/// The recount didn't match either; it's saved. Give a reason to close.
final class ReasonNeeded extends CountResult {
  const ReasonNeeded();
}

/// A shift as the supervisor's Shifts screen lists it.
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
    this.voidedAfterClose = const VoidedAfterClose(cash: 0, paybill: 0),
    this.needsReview = false,
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

  /// Its payments voided after it closed (BR-11); the figures above stay
  /// as counted.
  final VoidedAfterClose voidedAfterClose;

  /// Closed with a count that didn't match even on the recount (Story B).
  final bool needsReview;

  bool get isOpen => closedAt == null;
}

/// The domain's [drawerChain] (the repository's method of the same name
/// hides it inside the class).
List<ChainEntry> _chainOf({
  required List<ChainShift> shifts,
  required List<DrawerStartRecord> starts,
}) => drawerChain(shifts: shifts, starts: starts);

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

  // ── The drawer (Story B) ─────────────────────────────────────────────

  /// Every count the drawer's balance starts again from: the drawer's own
  /// counts, then closing counts (a close wins a tie: a count during a
  /// shift comes before its close).
  Future<List<DrawerAnchor>> _anchors() async => [
    for (final d in await _db.select(_db.drawerEvents).get())
      DrawerAnchor(
        id: d.id,
        kind: AnchorKind.values.byName(d.kind),
        at: d.countedAt,
        counted: d.counted,
        removed: d.removed,
      ),
    for (final s in await (_db.select(
      _db.shifts,
    )..where((s) => s.status.equals('closed'))).get())
      DrawerAnchor(
        id: s.id,
        kind: AnchorKind.close,
        at: s.closedAt!,
        counted: s.countedCash!,
      ),
  ];

  /// Whether the drawer has been counted at least once.
  Future<bool> drawerStarted() async => (await _anchors()).isNotEmpty;

  /// The supervisor or owner counts the starting cash, once, before the
  /// first shift (`drawer.start`). Throws [NotPermitted] or
  /// [DrawerRefused].
  Future<void> startDrawer(UserAccount user, {required int counted}) async {
    requirePermission(user, Permission.checkDrawer);
    if (countError(counted) case final problem?) throw DrawerRefused(problem);
    await _audit.writeWithAudit(
      action: 'drawer.start',
      userId: user.id,
      body: (w) async {
        if ((await _anchors()).isNotEmpty) {
          throw const DrawerRefused('The starting cash was already counted.');
        }
        await w.insert(
          _db.drawerEvents,
          DrawerEventsCompanion.insert(
            kind: 'start',
            countedBy: user.id,
            counted: counted,
            countedAt: w.now,
          ),
        );
      },
    );
  }

  /// What the drawer should hold now. Needs [Permission.viewShiftTotals].
  Future<int?> drawerNow(UserAccount user) async {
    requirePermission(user, Permission.viewShiftTotals);
    final open = await openShiftOnThisDevice();
    return drawerExpectedNow(
      latest: openingFloatFrom(await _anchors())?.balance,
      openFloat: open?.openingFloat,
      openCashNet: open == null ? 0 : (await takings(open.id)).cash.net,
    );
  }

  /// The drawer's history, newest first. Needs
  /// [Permission.viewShiftTotals].
  Future<List<ChainEntry>> drawerChain(UserAccount user) async {
    requirePermission(user, Permission.viewShiftTotals);
    final names = {
      for (final u in await _db.select(_db.users).get()) u.id: u.fullName,
    };
    return _chainOf(
      shifts: [
        for (final s in await _db.select(_db.shifts).get())
          ChainShift(
            id: s.id,
            userName: names[s.userId] ?? '',
            openedAt: s.openedAt,
            openingFloat: s.openingFloat,
            closedAt: s.closedAt,
            expectedCash: s.expectedCash,
            firstCount: s.firstCount,
            counted: s.status == 'closed' ? s.countedCash : null,
            needsReview: s.needsReview,
            note: s.closeNote,
          ),
      ],
      starts: [
        for (final d in await (_db.select(
          _db.drawerEvents,
        )..where((d) => d.kind.equals('start'))).get())
          DrawerStartRecord(
            id: d.id,
            at: d.countedAt,
            counted: d.counted,
            by: names[d.countedBy] ?? '',
          ),
      ],
    );
  }

  /// [drawerChain], watched.
  Stream<List<ChainEntry>> watchDrawerChain(UserAccount user) {
    requirePermission(user, Permission.viewShiftTotals);
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.shifts, _db.drawerEvents, _db.users},
        )
        .watch()
        .asyncMap((_) => drawerChain(user));
  }

  /// A shift's takings so far, for those who may see them (the resume
  /// card, the review). Needs [Permission.viewShiftTotals].
  Future<ShiftTakings> shiftFigures(UserAccount user, String shiftId) async {
    requirePermission(user, Permission.viewShiftTotals);
    return takings(shiftId);
  }

  /// The count tolerance in KES, owner only (`setCashRules`,
  /// `settings.update`).
  Future<void> setCountTolerance(UserAccount user, int kes) async {
    requirePermission(user, Permission.setCashRules);
    if (kes < 0) throw ArgumentError('The tolerance cannot be negative.');
    const key = SettingKeys.shiftCountTolerance;
    final stored = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    await _audit.writeWithAudit(
      action: 'settings.update',
      userId: user.id,
      body: (w) async {
        if (stored != null) {
          await w.update(
            _db.settings,
            key,
            SettingsCompanion(value: Value('$kes'), updatedBy: Value(user.id)),
          );
        } else {
          await w.insert(
            _db.settings,
            SettingsCompanion.insert(
              key: key,
              value: '$kes',
              updatedBy: Value(user.id),
            ),
          );
        }
      },
    );
  }

  Future<int> _tolerance() async {
    const key = SettingKeys.shiftCountTolerance;
    final stored = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return int.tryParse(stored?.value ?? settingDefaults[key]!) ?? 0;
  }

  /// Opens a shift for [user] (`shift.open`). The float is the drawer's
  /// balance at the last count, never typed; before the starting cash is
  /// counted, throws [NoStartingCash].
  Future<OpenShift> openShift({required UserAccount user}) async {
    requirePermission(user, Permission.openShift);
    final row = await _audit.writeWithAudit(
      action: 'shift.open',
      userId: user.id,
      body: (w) async {
        final existing = await openShiftOnThisDevice();
        if (existing != null) throw ShiftAlreadyOpen(existing);
        final anchor = openingFloatFrom(await _anchors());
        if (anchor == null) throw const NoStartingCash();
        return w.insert(
          _db.shifts,
          ShiftsCompanion.insert(
            userId: user.id,
            openedAt: w.now,
            openingFloat: anchor.balance,
            status: 'open',
            openedFrom: Value(anchor.id),
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

  // ── Closing: the blind count (FD-11, Story B) ──────────────────────────

  Future<ShiftRow> _closable(UserAccount user, String shiftId) async {
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
    return shift;
  }

  /// Where [shiftId]'s close is: the first count, the recount or the
  /// reason. Read from the shift, so leaving and coming back never gives
  /// another try.
  Future<CountStage> countStageOf(String shiftId) async {
    final s = await (_db.select(
      _db.shifts,
    )..where((s) => s.id.equals(shiftId))).getSingle();
    return countStage(firstCount: s.firstCount, recount: s.countedCash);
  }

  /// One blind count of [shiftId]'s drawer by [user]. Matching closes the
  /// shift (`shift.close`); not matching saves it (`shift.count_mismatch`)
  /// and asks once more, then for a reason ([closeWithReason]). The counter
  /// learns only which of the three it is. Throws [NotPermitted] or
  /// [ShiftCloseRefused].
  Future<CountResult> submitCount(
    UserAccount user,
    String shiftId,
    int count,
  ) async {
    if (countError(count) case final problem?) {
      throw ShiftCloseRefused(problem);
    }
    final shift = await _closable(user, shiftId);
    final stage = countStage(
      firstCount: shift.firstCount,
      recount: shift.countedCash,
    );
    if (stage == CountStage.reason) {
      throw const ShiftCloseRefused(reasonNeededMessage);
    }
    final figures = closeFigures(
      await takings(shiftId),
      openingFloat: shift.openingFloat,
      firstCount: shift.firstCount ?? count,
      counted: count,
    );
    if (countMatches(
      count,
      expected: figures.expectedCash,
      tolerance: await _tolerance(),
    )) {
      return CountClosed(
        await _close(user, shiftId, figures, needsReview: false, note: null),
      );
    }
    await _audit.writeWithAudit(
      action: 'shift.count_mismatch',
      userId: user.id,
      body: (w) => w.update(
        _db.shifts,
        shiftId,
        stage == CountStage.first
            ? ShiftsCompanion(firstCount: Value(count))
            : ShiftsCompanion(countedCash: Value(count)),
      ),
    );
    return stage == CountStage.first
        ? const CountAgain()
        : const ReasonNeeded();
  }

  /// Closes [shiftId] after two counts that didn't match, with [reason]
  /// (required): the close needs review. BR-12 is never blocked. Throws
  /// [NotPermitted] or [ShiftCloseRefused].
  Future<CloseFigures> closeWithReason(
    UserAccount user,
    String shiftId,
    String reason,
  ) async {
    final shift = await _closable(user, shiftId);
    if (countStage(firstCount: shift.firstCount, recount: shift.countedCash) !=
        CountStage.reason) {
      throw const ShiftCloseRefused('Count the cash first.');
    }
    if (closeReasonError(reason) case final problem?) {
      throw ShiftCloseRefused(problem);
    }
    return _close(
      user,
      shiftId,
      closeFigures(
        await takings(shiftId),
        openingFloat: shift.openingFloat,
        firstCount: shift.firstCount!,
        counted: shift.countedCash!,
      ),
      needsReview: true,
      note: reason.trim(),
    );
  }

  Future<CloseFigures> _close(
    UserAccount user,
    String shiftId,
    CloseFigures figures, {
    required bool needsReview,
    required String? note,
  }) => _audit.writeWithAudit(
    action: 'shift.close',
    userId: user.id,
    body: (w) async {
      final shift = await _closable(user, shiftId);
      await w.update(
        _db.shifts,
        shift.id,
        ShiftsCompanion(
          status: const Value('closed'),
          closedAt: Value(w.now),
          expectedCash: Value(figures.expectedCash),
          expectedPaybill: Value(figures.expectedPaybill),
          firstCount: Value(figures.firstCount),
          countedCash: Value(figures.counted),
          variance: Value(figures.variance),
          closeNote: Value(note),
          closedBy: Value(user.id),
          needsReview: Value(needsReview),
        ),
      );
      return figures;
    },
  );

  /// The newest [limit] shifts on this device, open ones included, for the
  /// supervisor's Shifts screen. Watched, so a close shows at once.
  /// Voids refresh it too: a payment voided after a close shows beside it.
  Stream<List<ShiftSummary>> watchShifts({int limit = 50}) {
    Future<List<ShiftSummary>> load() async {
      final rows =
          await (_db.select(_db.shifts)
                ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
                ..limit(limit))
              .get();
      final names = {
        for (final u in await _db.select(_db.users).get()) u.id: u.fullName,
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
            needsReview: s.needsReview,
            voidedAfterClose: s.closedAt == null
                ? const VoidedAfterClose(cash: 0, paybill: 0)
                : await _voidedAfterClose(s.id, s.closedAt!),
          ),
      ];
    }

    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.shifts, _db.voids, _db.payments},
        )
        .watch()
        .asyncMap((_) => load());
  }

  Future<VoidedAfterClose> _voidedAfterClose(
    String shiftId,
    DateTime closedAt,
  ) async {
    final payments = await (_db.select(
      _db.payments,
    )..where((p) => p.shiftId.equals(shiftId))).get();
    final voids =
        await (_db.select(_db.voids)..where(
              (v) =>
                  v.targetType.equals('payment') &
                  v.targetId.isIn([for (final p in payments) p.id]),
            ))
            .get();
    return voidedAfterClose(
      closedAt: closedAt,
      payments: [
        for (final p in payments)
          (id: p.id, amount: p.amount, method: PaymentMethod.parse(p.method)),
      ],
      voidedAt: {for (final v in voids) v.targetId: v.voidedAt},
    );
  }

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
