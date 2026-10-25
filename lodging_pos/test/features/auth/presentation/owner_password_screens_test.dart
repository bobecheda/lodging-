import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/owner_password.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';

import '../../../helpers/fake_cloud.dart';
import '../../../helpers/fixtures.dart';

/// The owner's password on the desk's screens (owner-app-3).
void main() {
  late TestEnv env;
  late UserAccount owner;
  late FakeCloud cloud;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 25, 9));
    await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    cloud = env.cloud = FakeCloud(serverNow: () => env.clock.now());
  });
  tearDown(() => env.close());

  /// Connects this desk before the app starts, as an earlier session did,
  /// then the owner changes their password on the phone and this desk
  /// pulls it.
  Future<void> changedOnPhoneBefore() async {
    final engine = SyncEngine(
      db: env.db,
      audit: env.audit,
      cloud: cloud,
      secrets: env.deskSecrets,
      clock: env.clock,
    );
    await engine.start();
    await engine.connect(
      owner: owner,
      installCode: 'ABCD-EFGH-JKLM',
      ownerEmail: testOwnerEmail,
      password: testOwner.password,
    );
    cloud.phoneChangesPassword('set-on-phone-1');
    await engine.pullNow();
    await engine.ownerLeft();
    cloud.dropDeskSession();
  }

  testWidgets('after a change on the phone, the old password gets the '
      'message at sign-in', (tester) async {
    await changedOnPhoneBefore();
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', testOwner.password);
    expect(find.text(passwordChangedOnPhone), findsOneWidget);
  });

  testWidgets('"Change my password" isn’t in a supervisor’s sidebar', (
    tester,
  ) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    expect(find.byKey(const ValueKey('shell.changeMyPassword')), findsNothing);
  });

  testWidgets('the owner’s dialog: mismatch, then the change, here only '
      'before connecting', (tester) async {
    env.cloud = null;
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', testOwner.password);
    await tapKey(tester, 'shell.changeMyPassword');
    await enterKey(tester, 'myPassword.current', testOwner.password);
    await enterKey(tester, 'myPassword.new', 'set-at-desk-1');
    await enterKey(tester, 'myPassword.repeat', 'set-at-desk-2');
    await tapKey(tester, 'myPassword.save');
    expect(find.text('The new passwords don’t match.'), findsOneWidget);
    await enterKey(tester, 'myPassword.repeat', 'set-at-desk-1');
    await tapKey(tester, 'myPassword.save');
    expect(find.byKey(const ValueKey('myPassword.dialog')), findsNothing);
    expect(await env.auditFor('user.change_password'), hasLength(1));
  });
}
