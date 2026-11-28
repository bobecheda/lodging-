import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/sync/desk_behind.dart';
import 'package:lodging_pos/core/sync/desk_secret_store.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/core/sync/sync_status_text.dart';
import 'package:lodging_pos/core/sync/sync_store.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../helpers/fake_cloud.dart';
import '../../helpers/fixtures.dart';

/// "This desk's data is behind the cloud" in the engine
/// (story/desk-db-guards-2): checked before the first push of every
/// session, and proved by a refused receipt number, a second open shift or
/// a pulled decision about something the file doesn't have. Sync then
/// stops for good, the evidence is kept and audited.
void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount supervisor;
  late FakeCloud cloud;
  late MemoryDeskSecretStore secrets;
  late SyncStore store;
  late SyncEngine engine;
  late String device;

  SyncEngine newEngine() => SyncEngine(
    db: env.db,
    audit: env.audit,
    cloud: cloud,
    secrets: secrets,
    clock: env.clock,
  );

  Future<String> bed(String number) async =>
      (await RoomsRepository(env.db, env.audit).createRoom(
        supervisor,
        NewRoom(
          number: number,
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: null,
        ),
      )).beds.single.id;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 11, 11, 10));
    supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    cloud = FakeCloud(serverNow: () => env.clock.now());
    secrets = MemoryDeskSecretStore();
    store = SyncStore(env.db);
    device = await env.db.deviceId();
    engine = newEngine();
    await engine.start();
    await engine.connect(
      owner: owner,
      installCode: 'abcd-efgh-jklm',
      ownerEmail: testOwnerEmail,
      password: testOwner.password,
    );
    expect(engine.status.phase, SyncPhase.online);
  });
  tearDown(() async {
    await engine.dispose();
    await env.close();
  });

  /// A new session of the app on the same file.
  Future<void> restart() async {
    await engine.dispose();
    engine = newEngine();
    await engine.start();
  }

  /// What a lost copy of this file sent: an audit row newer than anything
  /// here.
  void cloudHasNewerRecords() => cloud.holdsAlready('audit_log', {
    'id': 'lost-audit',
    'created_at': env.clock
        .now()
        .add(const Duration(hours: 1))
        .toIso8601String(),
    'updated_at': env.clock.now().toIso8601String(),
    'device_id': device,
    'at': env.clock.now().toIso8601String(),
    'operation_id': 'lost-op',
    'user_id': supervisor.id,
    'action': 'user.lock',
    'entity': 'users',
    'entity_id': supervisor.id,
    'before_json': null,
    'after_json': '{}',
  });

  group('checked before the first push of every session', () {
    test(
      'a file that matches the cloud: asked once, then sync goes on',
      () async {
        final asks = cloud.cloudStateAsks.length;
        await bed('5');
        await engine.syncNow();
        await bed('6');
        await engine.syncNow();
        expect(cloud.cloudStateAsks.length, asks, reason: 'once a session');
        expect(engine.status.phase, SyncPhase.online);

        await restart();
        expect(cloud.cloudStateAsks.length, asks + 1);
        expect(await store.unsent(limit: 10), isEmpty);
      },
    );

    test('the cloud has newer records from this desk: behind, nothing '
        'sent, audited and kept', () async {
      await engine.syncNow();
      cloudHasNewerRecords();
      await restart();
      final pushes = cloud.pushes.length;
      await bed('7');
      await engine.syncNow();

      expect(engine.status.phase, SyncPhase.behind);
      expect(engine.status.behind!.reasons, [BehindReason.missingRecords]);
      expect(cloud.pushes.length, pushes, reason: 'nothing sent');
      expect(await store.behind(), isNotNull);
      final audit = await env.auditFor('desk.behind_cloud');
      expect(audit, hasLength(1));
      expect(audit.single.afterJson, contains('missingRecords'));

      // Kept: the next session never asks or sends again.
      await restart();
      final asks = cloud.cloudStateAsks.length;
      await bed('8');
      await engine.syncNow();
      expect(engine.status.phase, SyncPhase.behind);
      expect(cloud.cloudStateAsks.length, asks);
      expect(cloud.pushes.length, pushes);
      expect(await env.auditFor('desk.behind_cloud'), hasLength(1));
    });

    test('checkCloud says so to the startup check; offline it can\'t tell, '
        'and nothing is sent until it can', () async {
      cloud.offline = true;
      await restart();
      expect(await engine.checkCloud(), isNull);
      expect(engine.status.phase, SyncPhase.offline);
      await bed('9');

      cloud.offline = false;
      cloudHasNewerRecords();
      final pushes = cloud.pushes.length;
      final evidence = await engine.checkCloud();
      expect(evidence!.reasons, [BehindReason.missingRecords]);
      await engine.syncNow();
      expect(cloud.pushes.length, pushes);
    });
  });

  group('refusals that prove it', () {
    test(
      'the cloud already has this receipt number: behind, no retry',
      () async {
        await engine.syncNow();
        // A lost copy took R-000001 (its audit rows never made it here).
        cloud.holdsAlready('payments', {
          'id': 'lost-payment',
          'created_at': env.clock.now().toIso8601String(),
          'updated_at': env.clock.now().toIso8601String(),
          'device_id': device,
          'receipt_number': 'R-000001',
          'shift_id': 'lost-shift',
          'received_by': supervisor.id,
          'received_at': env.clock.now().toIso8601String(),
          'amount': 700,
          'method': 'cash',
          'mpesa_code': null,
          'print_count': 1,
        });
        await env.checkIn(await bed('5'), by: supervisor);
        await engine.pushNow();

        expect(engine.status.phase, SyncPhase.behind);
        expect(engine.status.behind!.reasons, [BehindReason.receiptTaken]);
        expect(engine.status.behind!.detail, 'R-000001');
        expect(engine.retryAt, isNull, reason: 'never retried');
        expect(
          syncPillText(engine.status, pending: 1, now: env.clock.now()),
          'This desk’s data is behind the cloud',
        );
        expect(syncTone(engine.status.phase), SyncTone.problem);
      },
    );

    test(
      'the cloud already has an open shift from this desk: behind',
      () async {
        await engine.syncNow();
        cloud.holdsAlready('shifts', {
          'id': 'lost-shift',
          'created_at': env.clock.now().toIso8601String(),
          'updated_at': env.clock.now().toIso8601String(),
          'device_id': device,
          'user_id': supervisor.id,
          'opened_at': env.clock.now().toIso8601String(),
          'opening_float': 0,
          'status': 'open',
        });
        await env.openShift(supervisor);
        await engine.pushNow();
        expect(engine.status.phase, SyncPhase.behind);
        expect(engine.status.behind!.reasons, [BehindReason.openShiftTaken]);
      },
    );
  });

  test('a pulled review of a shift this file doesn\'t have: behind, not '
      'applied', () async {
    await engine.syncNow();
    cloud.holdsAlready('cash_reviews', {
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
    await engine.pullNow();

    expect(engine.status.phase, SyncPhase.behind);
    expect(engine.status.behind!.reasons, [BehindReason.missingSubject]);
    expect(
      engine.status.behind!.lines().single,
      'The cloud has a review of shift 37441d06, which this PC doesn’t have.',
    );
    expect(await env.db.select(env.db.cashReviews).get(), isEmpty);
  });
}
