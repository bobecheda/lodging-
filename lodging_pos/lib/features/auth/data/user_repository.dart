import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/database/database.dart';
import '../domain/credentials.dart';
import '../domain/setup.dart';

/// A user with the stored password hash. Stays in the data layer.
class StoredUser {
  const StoredUser(this.account, this.passwordHash);
  final UserAccount account;
  final String passwordHash;
}

/// The owner's account was being created when one already exists, or
/// first-run setup when any user exists.
class SetupAlreadyDone implements Exception {
  const SetupAlreadyDone();

  @override
  String toString() => 'This lodging is already set up';
}

/// The username is someone else's.
class UsernameTaken implements Exception {
  const UsernameTaken();

  @override
  String toString() => 'That username is taken.';
}

class UserRepository {
  UserRepository(this._db, this._audit, this._hasher);

  final AppDatabase _db;
  final AuditWriter _audit;
  final PasswordHasher _hasher;

  Future<bool> hasAnyUser() async =>
      await (_db.select(_db.users)..limit(1)).getSingleOrNull() != null;

  /// Whether an owner's account exists (enabled or not).
  Future<bool> hasOwner() async =>
      await (_db.select(_db.users)
            ..where((u) => u.role.equals(Role.owner.name))
            ..limit(1))
          .getSingleOrNull() !=
      null;

  /// Where first-run setup stands: no users yet, users but no owner (a
  /// database from before the owner role), or done.
  Future<SetupState> setupState() async {
    if (!await hasAnyUser()) return SetupState.fresh;
    if (!await hasOwner()) return SetupState.needsOwner;
    return SetupState.ready;
  }

  /// [username] is normalized before lookup.
  Future<StoredUser?> findByUsername(String username) async {
    final row =
        await (_db.select(_db.users)
              ..where((u) => u.username.equals(normalizeUsername(username))))
            .getSingleOrNull();
    return row == null ? null : StoredUser(_toAccount(row), row.passwordHash);
  }

  /// Fresh install: creates the owner and sets the lodging name in one
  /// transaction (one `operation_id`): `user.create` (role owner) +
  /// `settings.update`, both with the new owner as the user. The owner then
  /// adds the supervisor. Throws [SetupAlreadyDone] if any user exists,
  /// checked inside the transaction so two attempts can't both succeed.
  Future<UserAccount> createFirstOwner(SetupInput input) =>
      _createOwner(input, setLodgingName: true);

  /// A database from before the owner role: creates the owner's account
  /// (`user.create`, role owner), once. Only from the start-up screen,
  /// before anyone signs in: no screen inside the app creates an owner.
  /// Throws [SetupAlreadyDone] if an owner exists.
  Future<UserAccount> createMissingOwner(SetupInput input) =>
      _createOwner(input, setLodgingName: false);

  Future<UserAccount> _createOwner(
    SetupInput input, {
    required bool setLodgingName,
  }) async {
    final errors = validateSetup(input, withLodgingName: setLodgingName);
    if (errors.isNotEmpty) throw ArgumentError('Setup form is not valid');
    final setup = input.normalized();
    final hash = await _hasher.hash(setup.password);
    // Known up front so the audit rows can name the owner as their user.
    final ownerId = const Uuid().v4();

    final row = await _audit.writeWithAudit(
      action: 'user.create',
      userId: ownerId,
      body: (w) async {
        if (setLodgingName ? await hasAnyUser() : await hasOwner()) {
          throw const SetupAlreadyDone();
        }
        final taken = await (_db.select(
          _db.users,
        )..where((u) => u.username.equals(setup.username))).getSingleOrNull();
        if (taken != null) throw const UsernameTaken();
        final user = await w.insert(
          _db.users,
          UsersCompanion.insert(
            id: Value(ownerId),
            fullName: setup.fullName,
            username: setup.username,
            passwordHash: hash,
            role: Role.owner.name,
            mustChangePassword: false,
          ),
        );
        if (setLodgingName) {
          await w.update(
            _db.settings,
            'lodging_name',
            SettingsCompanion(
              value: Value(setup.lodgingName),
              updatedBy: Value(ownerId),
            ),
            action: 'settings.update',
          );
        }
        return user;
      },
    );
    return _toAccount(row);
  }

  /// Sets a new password and clears `must_change_password`.
  Future<UserAccount> changePassword(String userId, String newPassword) async {
    final problem = passwordError(newPassword);
    if (problem != null) throw ArgumentError(problem);
    final hash = await _hasher.hash(newPassword);
    final row = await _audit.writeWithAudit(
      action: 'user.change_password',
      userId: userId,
      body: (w) => w.update(
        _db.users,
        userId,
        UsersCompanion(
          passwordHash: Value(hash),
          mustChangePassword: const Value(false),
        ),
      ),
    );
    return _toAccount(row);
  }

  static UserAccount _toAccount(UserRow row) => UserAccount(
    id: row.id,
    fullName: row.fullName,
    username: row.username,
    role: Role.parse(row.role),
    isActive: row.isActive,
    mustChangePassword: row.mustChangePassword,
  );
}
