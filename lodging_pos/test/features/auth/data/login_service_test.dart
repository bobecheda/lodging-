import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/features/auth/data/login_service.dart';
import 'package:lodging_pos/features/auth/domain/login.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late LoginService login;

  setUp(() async {
    env = TestEnv();
    login = LoginService(env.users, env.hasher, env.audit);
    await env.addReceptionist('desk');
  });
  tearDown(() => env.close());

  test('the right password signs in and audits user.login', () async {
    final result = await login.login('desk', 'desk-pass');
    expect(result.outcome, LoginOutcome.success);
    expect(result.user!.username, 'desk');
    final entry = (await env.auditFor('user.login')).single;
    expect(entry.userId, result.user!.id);
    expect(entry.entityId, result.user!.id);
  });

  test('username is matched ignoring case and spaces', () async {
    final result = await login.login('  DESK ', 'desk-pass');
    expect(result.outcome, LoginOutcome.success);
  });

  test(
    'a wrong password fails and audits user.login_failed with no user',
    () async {
      final result = await login.login('desk', 'wrong-pass');
      expect(result.outcome, LoginOutcome.invalidCredentials);
      expect(result.user, isNull);
      final entry = (await env.auditFor('user.login_failed')).single;
      expect(entry.userId, isNull);
      expect(jsonDecode(entry.afterJson), {
        'username': 'desk',
        'reason': 'invalidCredentials',
      });
      expect(entry.afterJson, isNot(contains('wrong-pass')));
    },
  );

  test('an unknown username fails the same way', () async {
    final result = await login.login('ghost', 'desk-pass');
    expect(result.outcome, LoginOutcome.invalidCredentials);
    expect((await env.auditFor('user.login_failed')).single.entityId, 'ghost');
  });

  test('a disabled user cannot sign in', () async {
    await env.addReceptionist('gone', isActive: false);
    final result = await login.login('gone', 'desk-pass');
    expect(result.outcome, LoginOutcome.disabled);
    expect(result.user, isNull);
    expect(await env.auditFor('user.login'), isEmpty);
  });

  test('must_change_password signs in but flags the change', () async {
    await env.addReceptionist('fresh', mustChangePassword: true);
    final result = await login.login('fresh', 'desk-pass');
    expect(result.outcome, LoginOutcome.mustChangePassword);
    expect(result.user!.mustChangePassword, isTrue);
    expect(await env.auditFor('user.login'), hasLength(1));
  });
}
