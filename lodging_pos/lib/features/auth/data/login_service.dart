import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/sync/cloud_writes.dart';
import '../domain/credentials.dart';
import '../domain/login.dart';
import 'user_repository.dart';

class LoginResult {
  const LoginResult(this.outcome, [this.user]);
  final LoginOutcome outcome;

  /// Set when [outcome] signs the user in.
  final UserAccount? user;
}

/// Offline login against the local users table, audited either way. The
/// owner's one exception (owner-app-3): once the cloud has recorded a
/// password change after this desk's copy, the copy is refused and the
/// password is checked by the cloud instead; if it passes, the copy follows.
class LoginService {
  LoginService(this._users, this._hasher, this._audit, {this._cloud});

  final UserRepository _users;
  final PasswordHasher _hasher;
  final AuditWriter _audit;
  final OwnerPasswordCloud? _cloud;

  /// Checked against when the username is unknown, so a wrong username takes
  /// as long as a wrong password.
  Future<String>? _dummyHash;

  Future<LoginResult> login(String username, String password) async {
    final name = normalizeUsername(username);
    final stored = name.isEmpty ? null : await _users.findByUsername(name);
    final cloud = _cloud;
    if (stored != null &&
        cloud != null &&
        can(stored.account, Permission.ownerCloudPassword) &&
        await cloud.isOwnerPasswordBehind()) {
      return _followCloud(stored, password, cloud);
    }
    final hash =
        stored?.passwordHash ??
        await (_dummyHash ??= _hasher.hash('timing-equaliser'));
    final verified = await _hasher.verify(password, hash);
    final outcome = evaluateLogin(
      user: stored?.account,
      passwordMatches: stored != null && verified,
    );

    if (outcome.signsIn) {
      final user = stored!.account;
      await _audit.recordEvent(
        action: 'user.login',
        userId: user.id,
        entity: 'users',
        entityId: user.id,
      );
      return LoginResult(outcome, user);
    }
    await _audit.recordEvent(
      action: 'user.login_failed',
      userId: null,
      entity: 'users',
      entityId: stored?.account.id ?? name,
      details: {'username': name, 'reason': outcome.name},
    );
    return LoginResult(outcome);
  }

  /// The owner's copy here is behind the cloud's: only the cloud can say
  /// whether [password] is right. If it is, this desk keeps it.
  Future<LoginResult> _followCloud(
    StoredUser stored,
    String password,
    OwnerPasswordCloud cloud,
  ) async {
    final id = stored.account.id;
    try {
      await cloud.confirmOwnerPassword(password);
    } on Exception {
      await _audit.recordEvent(
        action: 'user.login_failed',
        userId: null,
        entity: 'users',
        entityId: id,
        details: {
          'username': stored.account.username,
          'reason': LoginOutcome.passwordChangedElsewhere.name,
        },
      );
      return const LoginResult(LoginOutcome.passwordChangedElsewhere);
    }
    final user = await _users.passwordFromCloud(id, password);
    await cloud.ownerPasswordCaughtUp();
    await _audit.recordEvent(
      action: 'user.login',
      userId: id,
      entity: 'users',
      entityId: id,
    );
    return LoginResult(LoginOutcome.success, user);
  }
}
