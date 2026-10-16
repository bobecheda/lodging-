import 'package:drift/drift.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../../auth/domain/credentials.dart';
import '../domain/staff.dart';

/// The add-receptionist form failed [validateNewReceptionist].
class InvalidReceptionist implements Exception {
  const InvalidReceptionist(this.errors);
  final Map<ReceptionistField, String> errors;
}

/// The housekeeper form failed [housekeeperErrors].
class InvalidHousekeeper implements Exception {
  const InvalidHousekeeper(this.errors);
  final Map<HousekeeperField, String> errors;
}

/// A staff rule refused the change; [message] is shown to the owner.
class StaffRuleViolation implements Exception {
  const StaffRuleViolation(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Users and housekeepers (AD-4). User writes need
/// [Permission.manageUsers], housekeeper writes
/// [Permission.manageHousekeepers]. Every write goes through writeWithAudit,
/// and every rule check runs inside its transaction.
class StaffRepository {
  StaffRepository(this._db, this._audit, this._hasher);

  final AppDatabase _db;
  final AuditWriter _audit;
  final PasswordHasher _hasher;

  // ── Users ──────────────────────────────────────────────────────────────

  /// Everyone who signs in: the owner first, then active users by name, then
  /// disabled ones; each with the time their open shift began, if any.
  Future<List<UserSummary>> users() async {
    final rows = await _db.select(_db.users).get();
    final open = await (_db.select(
      _db.shifts,
    )..where((s) => s.status.equals('open'))).get();
    final since = {for (final s in open) s.userId: s.openedAt};
    final list = [
      for (final r in rows)
        UserSummary(_toAccount(r), shiftOpenSince: since[r.id]),
    ];
    int rank(UserAccount u) => can(u, Permission.manageUsers)
        ? 0
        : u.isActive
        ? 1
        : 2;
    list.sort((a, b) {
      final byRank = rank(a.account) - rank(b.account);
      if (byRank != 0) return byRank;
      return a.account.fullName.toLowerCase().compareTo(
        b.account.fullName.toLowerCase(),
      );
    });
    return list;
  }

  /// Adds a receptionist who must set their own password at first sign-in
  /// (`user.create`).
  Future<UserAccount> addReceptionist(
    UserAccount actor,
    NewReceptionist input,
  ) async {
    requirePermission(actor, Permission.manageUsers);
    final errors = validateNewReceptionist(input);
    if (errors.isNotEmpty) throw InvalidReceptionist(errors);
    final form = input.normalized();
    final hash = await _hasher.hash(form.temporaryPassword);
    final row = await _audit.writeWithAudit(
      action: 'user.create',
      userId: actor.id,
      body: (w) async {
        final taken = await (_db.select(
          _db.users,
        )..where((u) => u.username.equals(form.username))).getSingleOrNull();
        if (taken != null) {
          throw const InvalidReceptionist({
            ReceptionistField.username: 'That username is taken.',
          });
        }
        return w.insert(
          _db.users,
          UsersCompanion.insert(
            fullName: form.fullName,
            username: form.username,
            passwordHash: hash,
            role: Role.receptionist.name,
            mustChangePassword: true,
          ),
        );
      },
    );
    return _toAccount(row);
  }

  /// Sets a temporary password the user must change at next sign-in
  /// (`user.reset_password`).
  Future<void> resetPassword(
    UserAccount actor,
    String userId,
    String temporaryPassword,
  ) async {
    requirePermission(actor, Permission.manageUsers);
    final problem = passwordError(temporaryPassword);
    if (problem != null) throw StaffRuleViolation(problem);
    final hash = await _hasher.hash(temporaryPassword);
    await _audit.writeWithAudit(
      action: 'user.reset_password',
      userId: actor.id,
      body: (w) async {
        await _requireManageable(actor, userId);
        await w.update(
          _db.users,
          userId,
          UsersCompanion(
            passwordHash: Value(hash),
            mustChangePassword: const Value(true),
          ),
        );
      },
    );
  }

  /// Disables an account so it can't sign in (`user.disable`). Allowed with
  /// an open shift; the screen warns first ([disableWarning]).
  Future<void> disableUser(UserAccount actor, String userId) =>
      _setUserActive(actor, userId, active: false);

  /// Lets a disabled account sign in again (`user.enable`);
  /// `must_change_password` is left as it was.
  Future<void> enableUser(UserAccount actor, String userId) =>
      _setUserActive(actor, userId, active: true);

  Future<void> _setUserActive(
    UserAccount actor,
    String userId, {
    required bool active,
  }) async {
    requirePermission(actor, Permission.manageUsers);
    final current = await _user(userId);
    if (current.isActive == active) return;
    await _audit.writeWithAudit(
      action: active ? 'user.enable' : 'user.disable',
      userId: actor.id,
      body: (w) async {
        await _requireManageable(actor, userId);
        await w.update(
          _db.users,
          userId,
          UsersCompanion(isActive: Value(active)),
        );
      },
    );
  }

  Future<UserRow> _user(String id) =>
      (_db.select(_db.users)..where((u) => u.id.equals(id))).getSingle();

  Future<void> _requireManageable(UserAccount actor, String userId) async {
    final blocker = accountActionBlocker(
      actor: actor,
      target: _toAccount(await _user(userId)),
    );
    if (blocker != null) throw StaffRuleViolation(blocker);
  }

  // ── Housekeepers ───────────────────────────────────────────────────────

  /// Active housekeepers by name, then inactive ones.
  Future<List<Housekeeper>> housekeepers() async {
    final rows = await _db.select(_db.housekeepers).get();
    final list = [for (final r in rows) _toHousekeeper(r)];
    list.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return list;
  }

  /// `housekeeper.create`.
  Future<Housekeeper> addHousekeeper(
    UserAccount actor, {
    required String name,
    required String phone,
  }) async {
    requirePermission(actor, Permission.manageHousekeepers);
    final form = _housekeeperForm(name, phone);
    final row = await _audit.writeWithAudit(
      action: 'housekeeper.create',
      userId: actor.id,
      body: (w) => w.insert(
        _db.housekeepers,
        HousekeepersCompanion.insert(
          fullName: form.fullName,
          phone: Value(form.phone),
        ),
      ),
    );
    return _toHousekeeper(row);
  }

  /// Changes the name and phone (`housekeeper.update`). Returns false when
  /// nothing changed.
  Future<bool> updateHousekeeper(
    UserAccount actor,
    String id, {
    required String name,
    required String phone,
  }) async {
    requirePermission(actor, Permission.manageHousekeepers);
    final form = _housekeeperForm(name, phone);
    final current = await _housekeeper(id);
    if (current.fullName == form.fullName && current.phone == form.phone) {
      return false;
    }
    await _audit.writeWithAudit(
      action: 'housekeeper.update',
      userId: actor.id,
      body: (w) => w.update(
        _db.housekeepers,
        id,
        HousekeepersCompanion(
          fullName: Value(form.fullName),
          phone: Value(form.phone),
        ),
      ),
    );
    return true;
  }

  /// `housekeeper.deactivate`. FD-9 adds the open-cleaning-task guard.
  Future<void> deactivateHousekeeper(UserAccount actor, String id) =>
      _setHousekeeperActive(actor, id, active: false);

  /// `housekeeper.reactivate`.
  Future<void> reactivateHousekeeper(UserAccount actor, String id) =>
      _setHousekeeperActive(actor, id, active: true);

  Future<void> _setHousekeeperActive(
    UserAccount actor,
    String id, {
    required bool active,
  }) async {
    requirePermission(actor, Permission.manageHousekeepers);
    if ((await _housekeeper(id)).isActive == active) return;
    await _audit.writeWithAudit(
      action: active ? 'housekeeper.reactivate' : 'housekeeper.deactivate',
      userId: actor.id,
      body: (w) => w.update(
        _db.housekeepers,
        id,
        HousekeepersCompanion(isActive: Value(active)),
      ),
    );
  }

  static NewHousekeeper _housekeeperForm(String name, String phone) {
    final errors = housekeeperErrors(name: name, phone: phone);
    if (errors.isNotEmpty) throw InvalidHousekeeper(errors);
    return NewHousekeeper.fromForm(name: name, phone: phone);
  }

  Future<HousekeeperRow> _housekeeper(String id) =>
      (_db.select(_db.housekeepers)..where((h) => h.id.equals(id))).getSingle();

  static Housekeeper _toHousekeeper(HousekeeperRow r) => Housekeeper(
    id: r.id,
    fullName: r.fullName,
    phone: r.phone,
    isActive: r.isActive,
  );

  static UserAccount _toAccount(UserRow r) => UserAccount(
    id: r.id,
    fullName: r.fullName,
    username: r.username,
    role: Role.parse(r.role),
    isActive: r.isActive,
    mustChangePassword: r.mustChangePassword,
  );
}
