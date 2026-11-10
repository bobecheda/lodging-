import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/clock.dart';
import '../../../core/database/database.dart';
import '../../../core/settings/setting_defaults.dart';
import '../domain/drawer.dart';
import '../domain/shift_close.dart';
import 'shift_repository.dart';

/// The saved count, for the collector's figures.
export '../../../core/database/database.dart' show DrawerEventRow;

/// The receptionist's co-sign was refused; [message] says why. Never says
/// any figure.
class CosignRefused implements Exception {
  const CosignRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Proof that [presentUserId] co-signed, with their own password, for
/// [counterId]'s count. Only [DrawerRepository.cosign] makes one (the
/// constructor is private to this library), and each is used once.
final class CosignToken {
  CosignToken._({
    required this.counterId,
    required this.presentUserId,
    required this.issuedAt,
  });

  final String id = const Uuid().v4();
  final String counterId;
  final String presentUserId;

  /// UTC.
  final DateTime issuedAt;
}

/// Drawer checks and weekly collections (Story B2) by the supervisor or the
/// owner, on the desk, with the receptionist present: they co-sign with
/// their own password first (a wrong one is refused and audited,
/// `drawer.cosign_failed`). The count is blind, as at close: one recount,
/// then a reason; a gap is recorded needing review. A collection then takes
/// away an amount no more than counted. Each count is a new anchor of the
/// drawer's ledger, so the next float follows. Audited `drawer.check` and
/// `drawer.collect`, with both names on the row.
class DrawerRepository {
  DrawerRepository(this._db, this._audit, this._hasher, this._clock)
    : _shifts = ShiftRepository(_db, _audit);

  final AppDatabase _db;
  final AuditWriter _audit;
  final PasswordHasher _hasher;
  final Clock _clock;
  final ShiftRepository _shifts;

  /// Co-signs last this long.
  static const cosignValidFor = Duration(minutes: 30);

  final _used = <String>{};

  static Permission _permissionFor(DrawerCountKind kind) => switch (kind) {
    DrawerCountKind.check => Permission.checkDrawer,
    DrawerCountKind.collect => Permission.collectCash,
  };

  UserAccount _account(UserRow u) => UserAccount(
    id: u.id,
    fullName: u.fullName,
    username: u.username,
    role: Role.parse(u.role),
    isActive: u.isActive,
    mustChangePassword: u.mustChangePassword,
  );

  /// Who must be present: the user of the shift open on this desk, or null
  /// when none is open (then [peopleWhoMayBePresent] are offered).
  Future<UserAccount?> presentForCount() async {
    final open = await _shifts.openShiftOnThisDevice();
    if (open == null) return null;
    return _account(
      await (_db.select(
        _db.users,
      )..where((u) => u.id.equals(open.userId))).getSingle(),
    );
  }

  /// With no shift open: the active desk staff other than [counter].
  Future<List<UserAccount>> peopleWhoMayBePresent(UserAccount counter) async =>
      [
        for (final u in await (_db.select(
          _db.users,
        )..orderBy([(u) => OrderingTerm.asc(u.fullName)])).get())
          if (u.id != counter.id && can(_account(u), Permission.openShift))
            _account(u),
      ];

  /// [presentUserId] co-signs [counter]'s count with their own [password].
  /// Throws [NotPermitted] (the counter may neither check nor collect) or
  /// [CosignRefused]; a wrong password is audited (`drawer.cosign_failed`).
  Future<CosignToken> cosign(
    UserAccount counter, {
    required String presentUserId,
    required String password,
  }) async {
    if (!can(counter, Permission.checkDrawer) &&
        !can(counter, Permission.collectCash)) {
      throw const NotPermitted(Permission.checkDrawer);
    }
    if (presentUserId == counter.id) {
      throw const CosignRefused(
        'The person present can’t be the one counting.',
      );
    }
    final open = await _shifts.openShiftOnThisDevice();
    if (open != null && open.userId != presentUserId) {
      throw CosignRefused(
        '${open.userName} is on shift: ${open.userName} co-signs.',
      );
    }
    final row = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(presentUserId))).getSingleOrNull();
    if (row == null || !can(_account(row), Permission.openShift)) {
      throw const CosignRefused('Choose who is at the desk.');
    }
    if (!await _hasher.verify(password, row.passwordHash)) {
      await _audit.recordEvent(
        action: 'drawer.cosign_failed',
        userId: counter.id,
        entity: 'users',
        entityId: presentUserId,
      );
      throw const CosignRefused('That password isn’t right.');
    }
    return CosignToken._(
      counterId: counter.id,
      presentUserId: presentUserId,
      issuedAt: _clock.now(),
    );
  }

  void _requireToken(UserAccount counter, CosignToken token) {
    if (token.counterId != counter.id ||
        _used.contains(token.id) ||
        _clock.now().difference(token.issuedAt) > cosignValidFor) {
      throw const CosignRefused('The receptionist needs to co-sign again.');
    }
  }

  Future<int> _tolerance() async {
    const key = SettingKeys.shiftCountTolerance;
    final stored = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return int.tryParse(stored?.value ?? settingDefaults[key]!) ?? 0;
  }

  /// Whether [count], a first count, matches what the drawer should hold.
  /// One that doesn't is audited (`drawer.count_mismatch`), so a count
  /// started again still leaves its trace. The counter learns only yes or
  /// no.
  Future<bool> firstCountMatches(
    UserAccount counter,
    CosignToken token,
    int count,
  ) async {
    _requireToken(counter, token);
    final expected = await _shifts.expectedNow();
    if (expected == null) throw const NoStartingCash();
    if (countError(count) case final p?) throw DrawerCountProblem(p);
    final matches = countMatches(
      count,
      expected: expected,
      tolerance: await _tolerance(),
    );
    if (!matches) {
      await _audit.recordEvent(
        action: 'drawer.count_mismatch',
        userId: counter.id,
        entity: 'users',
        entityId: token.presentUserId,
        details: {'first_count': count},
      );
    }
    return matches;
  }

  /// Records a check or a collection: [firstCount], the [recount] if the
  /// first didn't match, [note] if neither did (it then needs review), and
  /// for a collection the cash [removed] (0 up to what was counted). Throws
  /// [NotPermitted], [CosignRefused], [DrawerCountProblem],
  /// [DrawerRefused] or [NoStartingCash].
  Future<DrawerEventRow> recordCount(
    UserAccount counter,
    CosignToken token, {
    required DrawerCountKind kind,
    required int firstCount,
    int? recount,
    String? note,
    int removed = 0,
  }) async {
    requirePermission(counter, _permissionFor(kind));
    _requireToken(counter, token);
    final expected = await _shifts.expectedNow();
    if (expected == null) throw const NoStartingCash();
    final count = drawerCountOf(
      expected: expected,
      firstCount: firstCount,
      recount: recount,
      note: note,
      tolerance: await _tolerance(),
    );
    switch (kind) {
      case DrawerCountKind.collect:
        if (removedError(removed, counted: count.counted) case final p?) {
          throw DrawerRefused(p);
        }
      case DrawerCountKind.check:
        if (removed != 0) {
          throw const DrawerRefused('A check takes nothing away.');
        }
    }
    final open = await _shifts.openShiftOnThisDevice();
    if (open != null && open.userId != token.presentUserId) {
      throw const CosignRefused('The receptionist needs to co-sign again.');
    }
    final row = await _audit.writeWithAudit(
      action: 'drawer.${kind.code}',
      userId: counter.id,
      body: (w) => w.insert(
        _db.drawerEvents,
        DrawerEventsCompanion.insert(
          kind: kind.code,
          countedBy: counter.id,
          presentUser: Value(token.presentUserId),
          shiftId: Value(open?.id),
          firstCount: Value(count.firstCount),
          counted: count.counted,
          expected: Value(expected),
          removed: Value(removed),
          note: Value(count.note),
          needsReview: Value(count.needsReview),
          countedAt: w.now,
        ),
      ),
    );
    _used.add(token.id);
    return row;
  }
}
