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

/// First-run setup was attempted when a user already exists.
class SetupAlreadyDone implements Exception {
  const SetupAlreadyDone();

  @override
  String toString() => 'This lodging is already set up';
}

class UserRepository {
  UserRepository(this._db, this._audit, this._hasher);

  final AppDatabase _db;
  final AuditWriter _audit;
  final PasswordHasher _hasher;

  Future<bool> hasAnyUser() async =>
      await (_db.select(_db.users)..limit(1)).getSingleOrNull() != null;

  /// [username] is normalized before lookup.
  Future<StoredUser?> findByUsername(String username) async {
    final row =
        await (_db.select(_db.users)
              ..where((u) => u.username.equals(normalizeUsername(username))))
            .getSingleOrNull();
    return row == null ? null : StoredUser(_toAccount(row), row.passwordHash);
  }

  /// Creates the first supervisor and sets the lodging name in one
  /// transaction (one `operation_id`): `user.create` + `settings.update`,
  /// both with the new supervisor as the user. Throws [SetupAlreadyDone] if any user exists,
  /// checked inside the transaction so two attempts can't both succeed.
  Future<UserAccount> createFirstSupervisor(SetupInput input) async {
    if (validateSetup(input).isNotEmpty) {
      throw ArgumentError('Setup form is not valid');
    }
    final setup = input.normalized();
    final hash = await _hasher.hash(setup.password);
    // Known up front so the audit rows can name the supervisor as their user.
    final supervisorId = const Uuid().v4();

    final row = await _audit.writeWithAudit(
      action: 'user.create',
      userId: supervisorId,
      body: (w) async {
        if (await hasAnyUser()) throw const SetupAlreadyDone();
        final user = await w.insert(
          _db.users,
          UsersCompanion.insert(
            id: Value(supervisorId),
            fullName: setup.fullName,
            username: setup.username,
            passwordHash: hash,
            role: Role.supervisor.name,
            mustChangePassword: false,
          ),
        );
        await w.update(
          _db.settings,
          'lodging_name',
          SettingsCompanion(
            value: Value(setup.lodgingName),
            updatedBy: Value(supervisorId),
          ),
          action: 'settings.update',
        );
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
