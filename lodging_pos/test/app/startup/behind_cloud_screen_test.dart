import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/support_contact.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/core/sync/sync_providers.dart';

import '../../helpers/fake_cloud.dart';
import '../../helpers/fixtures.dart';

/// "This PC's data is older than the cloud" on the desk
/// (story/desk-db-guards-2): checked with the cloud before sign-in when
/// online; a refusal screen in plain words, with the details for the owner
/// only; mid-session a red banner and pill, and the refusal at the next
/// sign-in or lock.
void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late FakeCloud cloud;
  late String device;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 11, 24, 9, 51));
    supervisor = await env.createFirstSupervisor(testSetup);
    device = await env.db.deviceId();
    cloud = env.cloud = FakeCloud(serverNow: () => env.clock.now());
    // Connected in an earlier session.
    final engine = SyncEngine(
      db: env.db,
      audit: env.audit,
      cloud: cloud,
      secrets: env.deskSecrets,
      clock: env.clock,
    );
    await engine.start();
    await engine.connect(
      owner: env.owner!,
      installCode: 'ABCD-EFGH-JKLM',
      ownerEmail: testOwnerEmail,
      password: testOwner.password,
    );
    await engine.ownerLeft();
    await engine.dispose();
    cloud.dropDeskSession();
  });
  tearDown(() => env.close());

  /// What a lost copy of this file sent: records newer than anything here.
  void cloudHasNewerRecords() => cloud.holdsAlready('audit_log', {
    'id': 'lost-audit',
    'created_at': env.clock
        .now()
        .add(const Duration(minutes: 10))
        .toIso8601String(),
    'updated_at': env.clock.now().toIso8601String(),
    'device_id': device,
    'at': env.clock.now().toIso8601String(),
    'operation_id': 'lost-op',
    'user_id': supervisor.id,
    'action': 'shift.open',
    'entity': 'shifts',
    'entity_id': '37441d06-272e-4cb3-8455-918760f42006',
    'before_json': null,
    'after_json': '{}',
  });

  /// A pulled review of a shift this file doesn't have.
  void cloudHasAReviewOfALostShift() => cloud.holdsAlready('cash_reviews', {
    'id': 'lost-review',
    'created_at': env.clock.now().toIso8601String(),
    'updated_at': env.clock.now().toIso8601String(),
    'device_id': device,
    'target_type': 'shift',
    'target_id': '37441d06-272e-4cb3-8455-918760f42006',
    'decision': 'approved',
    'reason': null,
    'decided_by': supervisor.id,
    'decided_at': env.clock.now().toIso8601String(),
  });

  testWidgets('online at start and the cloud proves it: the refusal before '
      'sign-in, in plain words', (tester) async {
    cloudHasNewerRecords();
    final app = await pumpDeskApp(tester, env);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.behindCloud);
    expect(find.text(behindRefusalText), findsOneWidget);
    expect(find.byKey(const ValueKey('login.username')), findsNothing);
    expect(find.textContaining('duplicate key'), findsNothing);
    expect(await env.auditFor('desk.behind_cloud'), hasLength(1));
  });

  testWidgets('offline at start: the desk opens as today', (tester) async {
    cloudHasNewerRecords();
    cloud.offline = true;
    final app = await pumpDeskApp(tester, env);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.login);
  });

  testWidgets('found mid-session: a red banner and pill, sync stops; the '
      'refusal at the next lock', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    expect(find.byKey(const ValueKey('shell.behindBanner')), findsNothing);

    cloudHasAReviewOfALostShift();
    await app.read(syncEngineProvider)!.pullNow();
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.home, reason: 'finish with this guest');
    expect(find.text(behindBannerText), findsOneWidget);
    expect(find.text(SyncEngine.behindProblem), findsWidgets);

    await tapKey(tester, 'shell.lock');
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.behindCloud);
  });

  testWidgets('the details are the owner\'s, audited, and copy for Bobe', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    cloudHasNewerRecords();
    final app = await pumpDeskApp(tester, env);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.behindCloud);
    expect(find.byKey(const ValueKey('behind.lines')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('behind.username')),
      'supervisor',
    );
    await tester.enterText(
      find.byKey(const ValueKey('behind.password')),
      'super-pass',
    );
    await tapKey(tester, 'behind.details');
    expect(find.text('Only the owner can see the details.'), findsOneWidget);
    expect(find.byKey(const ValueKey('behind.lines')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('behind.username')),
      testOwner.username,
    );
    await tester.enterText(
      find.byKey(const ValueKey('behind.password')),
      testOwner.password,
    );
    await tapKey(tester, 'behind.details');
    expect(
      find.textContaining('records from this desk that this PC doesn’t have'),
      findsOneWidget,
    );
    await tapKey(tester, 'behind.copy');
    expect(copied, contains('records from this desk that this PC'));
    expect(copied, contains(device.substring(0, 8)));
    expect(await env.auditFor('desk.behind_details'), hasLength(1));
    // Still nothing unlocks the data.
    expect(locationOf(app), Routes.behindCloud);
  });

  for (final size in deskSizes) {
    testWidgets('the refusal and the banner fit at '
        '${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      cloudHasNewerRecords();
      final app = await pumpDeskApp(tester, env, size: size);
      await tester.pumpAndSettle();
      expect(locationOf(app), Routes.behindCloud);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the banner fits at '
        '${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      final app = await pumpDeskApp(tester, env, size: size);
      await signInAs(tester, 'supervisor', 'super-pass');
      cloudHasAReviewOfALostShift();
      await app.read(syncEngineProvider)!.pullNow();
      await tester.pumpAndSettle();
      expect(find.text(behindBannerText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
