import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/core/sync/sync_providers.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fake_cloud.dart';
import '../../../helpers/fixtures.dart';

/// sync-2 at the desk, live: what the phone decides shows without a
/// restart.
void main() {
  late TestEnv env;
  late UserAccount owner;
  late FakeCloud cloud;
  late String refundId;
  var serverAhead = Duration.zero;

  setUp(() async {
    serverAhead = Duration.zero;
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19));
    final supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    final desk = await env.addReceptionist('desk');
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
    final stay = await env.checkIn(room.beds.single.id, by: desk, nights: 3);
    env.clock.set(nairobiInstant(2026, 10, 16, 10, 30));
    await env.checkOut(stay, by: desk);
    refundId = (await env.db.select(env.db.refunds).getSingle()).id;

    cloud = env.cloud = FakeCloud(
      serverNow: () => env.clock.now().add(serverAhead),
    );
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
      owner: owner,
      installCode: 'ABCD-EFGH-JKLM',
      ownerEmail: testOwnerEmail,
      password: testOwner.password,
    );
    await engine.ownerLeft();
    cloud.dropDeskSession();
  });
  tearDown(() => env.close());

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  Future<void> pull(WidgetTester tester, ProviderContainer app) async {
    await app.read(syncEngineProvider)!.pullNow();
    await tester.pumpAndSettle();
  }

  testWidgets('the phone approves: the refund moves to TO PAY and the badge '
      'counts it, no restart', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    await tapKey(tester, 'nav.${Routes.refunds}');
    expect(find.byKey(ValueKey('refunds.pay.$refundId')), findsNothing);

    cloud.decideElsewhere(
      'refund_decisions',
      'refund_id',
      refundId,
      decision: 'approved',
      at: env.clock.now(),
    );
    await pull(tester, app);
    expect(find.byKey(ValueKey('refunds.pay.$refundId')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('nav.badge.${Routes.refunds}')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the phone rejects: the owner’s reason shows', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    await tapKey(tester, 'nav.${Routes.refunds}');
    cloud.decideElsewhere(
      'refund_decisions',
      'refund_id',
      refundId,
      decision: 'rejected',
      note: 'Guest agreed to stay on',
      at: env.clock.now(),
    );
    await pull(tester, app);
    expect(
      text(tester, 'refunds.reason.$refundId'),
      '“Guest agreed to stay on”',
    );
  });

  testWidgets('prices from the phone: an untouched field takes the new price; '
      'a typed one keeps its value, its hint showing the new price', (
    tester,
  ) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await tapKey(tester, 'nav.${Routes.adminPrices}');
    await enterKey(tester, 'price.${SeedIds.vip}', '1050');
    await tester.pump();

    cloud
      ..setPriceElsewhere(SeedIds.deluxe, 750, env.clock.now())
      ..setPriceElsewhere(SeedIds.vip, 1200, env.clock.now());
    await pull(tester, app);

    String field(String id) => tester
        .widget<TextField>(find.byKey(ValueKey('price.$id')))
        .controller!
        .text;
    expect(field(SeedIds.deluxe), '750');
    expect(field(SeedIds.vip), '1,050');
    expect(text(tester, 'price.was.${SeedIds.vip}'), 'was 1,200');
  });

  testWidgets('a PC clock 12 minutes slow: the pill says so and the panel '
      'gives the fix; nothing is blocked', (tester) async {
    serverAhead = const Duration(minutes: 12);
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    expect(find.text('PC clock 12 min slow · fix'), findsOneWidget);
    await tapKey(tester, 'shell.syncPill');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sync.clock')),
        matching: find.text(
          'PC clock is 12 min slow. Windows Settings → Time & language → '
          'Sync now',
        ),
      ),
      findsOneWidget,
    );
  });
}
