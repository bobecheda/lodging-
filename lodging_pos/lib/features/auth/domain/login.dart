import '../../../core/auth/user_account.dart';

enum LoginOutcome {
  success,

  /// Signed in, but nothing else is reachable until the password is changed.
  mustChangePassword,

  /// Unknown username or wrong password; deliberately indistinguishable.
  invalidCredentials,

  /// Right password, but the supervisor disabled the account.
  disabled;

  bool get signsIn => this == success || this == mustChangePassword;
}

/// [user] is null when the username is unknown. A disabled account is only
/// reported as disabled when the password is right, so the message reveals
/// nothing to someone guessing.
LoginOutcome evaluateLogin({
  required UserAccount? user,
  required bool passwordMatches,
}) {
  if (user == null || !passwordMatches) return LoginOutcome.invalidCredentials;
  if (!user.isActive) return LoginOutcome.disabled;
  if (user.mustChangePassword) return LoginOutcome.mustChangePassword;
  return LoginOutcome.success;
}
