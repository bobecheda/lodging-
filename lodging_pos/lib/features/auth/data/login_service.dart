import '../../../core/audit/audit_writer.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/auth/user_account.dart';
import '../domain/credentials.dart';
import '../domain/login.dart';
import 'user_repository.dart';

class LoginResult {
  const LoginResult(this.outcome, [this.user]);
  final LoginOutcome outcome;

  /// Set when [outcome] signs the user in.
  final UserAccount? user;
}

/// Offline login against the local users table, audited either way.
class LoginService {
  LoginService(this._users, this._hasher, this._audit);

  final UserRepository _users;
  final PasswordHasher _hasher;
  final AuditWriter _audit;

  /// Checked against when the username is unknown, so a wrong username takes
  /// as long as a wrong password.
  Future<String>? _dummyHash;

  Future<LoginResult> login(String username, String password) async {
    final name = normalizeUsername(username);
    final stored = name.isEmpty ? null : await _users.findByUsername(name);
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
}
