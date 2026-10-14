import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/auth/domain/login.dart';
import 'package:lodging_pos/core/auth/user_account.dart';

void main() {
  const desk = UserAccount(
    id: 'u1',
    fullName: 'Desk',
    username: 'desk',
    role: Role.receptionist,
    isActive: true,
    mustChangePassword: false,
  );

  LoginOutcome outcome(UserAccount? user, {bool passwordMatches = true}) =>
      evaluateLogin(user: user, passwordMatches: passwordMatches);

  test('an active user with the right password logs in', () {
    expect(outcome(desk), LoginOutcome.success);
  });

  test('unknown user and wrong password look the same', () {
    expect(outcome(null), LoginOutcome.invalidCredentials);
    expect(
      outcome(desk, passwordMatches: false),
      LoginOutcome.invalidCredentials,
    );
  });

  test('a disabled user cannot log in, even with the right password', () {
    expect(outcome(desk.copyWith(isActive: false)), LoginOutcome.disabled);
    expect(
      outcome(desk.copyWith(isActive: false), passwordMatches: false),
      LoginOutcome.invalidCredentials,
    );
  });

  test('a user who must change password is sent to change it', () {
    expect(
      outcome(desk.copyWith(mustChangePassword: true)),
      LoginOutcome.mustChangePassword,
    );
  });

  test('outcomes that sign the user in', () {
    expect(LoginOutcome.success.signsIn, isTrue);
    expect(LoginOutcome.mustChangePassword.signsIn, isTrue);
    expect(LoginOutcome.invalidCredentials.signsIn, isFalse);
    expect(LoginOutcome.disabled.signsIn, isFalse);
  });
}
