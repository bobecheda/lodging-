import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lodging_pos/core/audit/audit_writer.dart';
import 'package:lodging_pos/core/auth/password_hasher.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/database_provider.dart';
import 'package:lodging_pos/features/auth/data/user_repository.dart';
import 'package:lodging_pos/features/auth/domain/setup.dart';
import 'package:lodging_pos/features/auth/presentation/idle_lock.dart';

/// 22:00 Nairobi, 14 Oct 2026.
final testT0 = DateTime.utc(2026, 10, 14, 19);

const testSetup = SetupInput(
  fullName: 'Grace Owner',
  username: 'Owner',
  password: 'owner-pass',
  confirmPassword: 'owner-pass',
  lodgingName: 'Sunrise Lodge',
);

/// An in-memory database with the real writer and a fast hasher.
class TestEnv {
  TestEnv() : clock = FixedClock(testT0) {
    db = AppDatabase(NativeDatabase.memory(), clock: clock);
    audit = AuditWriter(db, clock);
    users = UserRepository(db, audit, hasher);
  }

  final FixedClock clock;
  final hasher = const PasswordHasher.fast();
  late final AppDatabase db;
  late final AuditWriter audit;
  late final UserRepository users;

  Future<void> close() => db.close();

  /// Provider overrides that run the real app against this environment.
  /// The idle-lock timer is off; tests call `IdleLock.check()` themselves.
  List<Override> get overrides => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    passwordHasherProvider.overrideWithValue(hasher),
    idleCheckIntervalProvider.overrideWithValue(null),
  ];

  /// Until AD-4 adds user management, tests create receptionists directly
  /// through the writer.
  Future<UserAccount> addReceptionist(
    String username, {
    String password = 'desk-pass',
    bool mustChangePassword = false,
    bool isActive = true,
  }) async {
    final hash = await hasher.hash(password);
    final row = await audit.writeWithAudit(
      action: 'user.create',
      userId: null,
      body: (w) => w.insert(
        db.users,
        UsersCompanion.insert(
          fullName: 'Desk ${username.toUpperCase()}',
          username: username,
          passwordHash: hash,
          role: Role.receptionist.name,
          mustChangePassword: mustChangePassword,
          isActive: Value(isActive),
        ),
      ),
    );
    return UserAccount(
      id: row.id,
      fullName: row.fullName,
      username: row.username,
      role: Role.receptionist,
      isActive: row.isActive,
      mustChangePassword: row.mustChangePassword,
    );
  }

  Future<List<AuditLogRow>> auditFor(String action) =>
      (db.select(db.auditLog)..where((a) => a.action.equals(action))).get();
}
