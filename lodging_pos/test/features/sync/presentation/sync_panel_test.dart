import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/core/sync/sync_providers.dart';
import 'package:lodging_pos/features/refunds/data/refunds_repository.dart';
import 'package:lodging_pos/features/refunds/domain/refund.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fake_cloud.dart';
import '../../../helpers/fixtures.dart';

/// A password changed on the phone (made up).
const phonePassword = 'changed-elsewhere';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late FakeCloud cloud;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19));
    await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    cloud = env.cloud = FakeCloud();
  });
  tearDown(() => env.close());

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  /// Connects this desk before the app starts, as an earlier session did.
  Future<void> connectedBefore() async {
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
    await engine.ownerLeft();
    cloud.dropDeskSession();
  }

  testWidgets('the owner connects this desk from the pill: the password is '
      'checked here first; then everything goes up', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    expect(find.textContaining('Not connected ·'), findsOneWidget);
    await tapKey(tester, 'shell.syncPill');
    expect(find.text('Cloud sync'), findsOneWidget);

    await tapKey(tester, 'sync.connect');
    expect(find.text('Enter the install code.'), findsOneWidget);
    await enterKey(tester, 'sync.code', 'abcd-efgh-jklm');
    await enterKey(tester, 'sync.email', testOwnerEmail);
    await enterKey(tester, 'sync.password', 'not-it');
    await tapKey(tester, 'sync.connect');
    expect(find.text('That isn’t your desk password.'), findsOneWidget);

    await enterKey(tester, 'sync.password', testOwner.password);
    await tapKey(tester, 'sync.connect');
    expect(text(tester, 'sync.state'), 'Online · synced just now');
    expect(cloud.devices.values.single, isTrue);
    expect(cloud.count('users'), 2);
    expect(app.read(syncEngineProvider)!.active, isTrue);
  });

  testWidgets('a wrong install code: the cloud’s reason, nothing stored', (
    tester,
  ) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await tapKey(tester, 'shell.syncPill');
    await enterKey(tester, 'sync.code', 'NOPE-NOPE-NOPE');
    await enterKey(tester, 'sync.email', testOwnerEmail);
    await enterKey(tester, 'sync.password', testOwner.password);
    await tapKey(tester, 'sync.connect');
    expect(
      find.text('That install code isn’t valid, has expired or has been used.'),
      findsOneWidget,
    );
    expect(await env.deskSecrets.read(), isNull);
  });

  testWidgets('the supervisor can see, not connect', (tester) async {
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    await tapKey(tester, 'shell.syncPill');
    expect(
      find.text(
        'This desk isn’t connected to the cloud yet. The owner connects '
        'it here.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sync.connect')), findsNothing);
  });

  testWidgets('connected before: online at start; offline, the pill counts '
      'what waits', (tester) async {
    await connectedBefore();
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'supervisor', 'super-pass');
    expect(find.text('Online · synced just now'), findsOneWidget);

    cloud.offline = true;
    await RoomsRepository(env.db, env.audit).createRoom(
      (await env.users.findByUsername('supervisor'))!.account,
      const NewRoom(
        number: '9',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    await app.read(syncEngineProvider)!.pushNow();
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline ·'), findsOneWidget);
  });

  testWidgets('the key is missing (another Windows user): the owner '
      'reconnects this desk', (tester) async {
    await connectedBefore();
    env.deskSecrets.credentials = null;
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    expect(find.text('Sync problem · details'), findsOneWidget);
    await tapKey(tester, 'shell.syncPill');
    expect(find.text('This desk needs reconnecting.'), findsOneWidget);
    await enterKey(tester, 'sync.email', testOwnerEmail);
    await enterKey(tester, 'sync.password', testOwner.password);
    await tapKey(tester, 'sync.connect');
    expect(text(tester, 'sync.state'), 'Online · synced just now');
  });

  testWidgets('approving without the owner’s cloud sign-in asks for the '
      'password once, then approves', (tester) async {
    final supervisor = (await env.users.findByUsername('supervisor'))!.account;
    final room = await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '5',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    final desk = await env.addReceptionist('desk');
    final stay = await env.checkIn(room.beds.single.id, by: desk, nights: 3);
    env.clock.set(nairobiInstant(2026, 10, 16, 10, 30));
    await env.checkOut(stay, by: desk);
    final refundId = (await env.db.select(env.db.refunds).getSingle()).id;
    await connectedBefore();

    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    // The quiet cloud sign-in at the desk failed (the phone changed it).
    await app.read(syncEngineProvider)!.ownerLeft();
    cloud.ownerPassword = phonePassword;

    await tapKey(tester, 'today.attention.refund.$refundId');
    expect(locationOf(app), Routes.refundDetail);
    await tapKey(tester, 'refund.approve');
    expect(find.text('Sign in to the cloud'), findsOneWidget);
    await enterKey(tester, 'ownerCloud.password', testOwner.password);
    await tapKey(tester, 'ownerCloud.signIn');
    expect(find.text('Wrong password. Try again.'), findsOneWidget);
    await enterKey(tester, 'ownerCloud.password', phonePassword);
    await tapKey(tester, 'ownerCloud.signIn');

    final status = (await RefundsRepository(env.db, env.audit).view(refundId))
        .status;
    expect(status, RefundStatus.approved);
    expect(cloud.count('refund_decisions'), 1);
  });
}
