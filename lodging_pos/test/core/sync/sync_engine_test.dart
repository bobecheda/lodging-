import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/sync/cloud.dart';
import 'package:lodging_pos/core/sync/cloud_writes.dart';
import 'package:lodging_pos/core/sync/desk_secret_store.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/core/sync/sync_store.dart';
import 'package:lodging_pos/features/refunds/data/refunds_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../helpers/fake_cloud.dart';
import '../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount supervisor;
  late FakeCloud cloud;
  late MemoryDeskSecretStore secrets;
  late SyncStore store;
  late SyncEngine engine;
  const ownerEmail = testOwnerEmail;

  SyncEngine newEngine() => SyncEngine(
    db: env.db,
    audit: env.audit,
    cloud: cloud,
    secrets: secrets,
    clock: env.clock,
    batchSize: 3,
  );

  Future<String> addRoom(String number) async =>
      (await RoomsRepository(env.db, env.audit).createRoom(
        supervisor,
        NewRoom(
          number: number,
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: null,
        ),
      )).id;

  /// A stay that left early, and the owner's approval, all before the desk
  /// is connected: the snapshot must carry the owner's decision too.
  Future<void> historyWithADecision() async {
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
    final refund = (await env.db.select(env.db.refunds).getSingle()).id;
    await RefundsRepository(
      env.db,
      env.audit,
    ).decide(owner, refund, approve: true);
  }

  Future<void> connect() => engine.connect(
    owner: owner,
    installCode: 'abcd-efgh-jklm',
    ownerEmail: ownerEmail,
    password: testOwner.password,
  );

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19));
    supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    cloud = FakeCloud(serverNow: () => env.clock.now());
    secrets = MemoryDeskSecretStore();
    store = SyncStore(env.db);
    engine = newEngine();
    await engine.start();
  });
  tearDown(() async {
    await engine.dispose();
    await env.close();
  });

  Future<void> expectCloudMatchesDesk() async {
    for (final table in [...SyncStore.deskTables, ...SyncStore.ownerTables]) {
      expect(
        cloud.count(table),
        await store.count(table),
        reason: '$table rows in the cloud',
      );
    }
  }

  test('not connected: nothing leaves the desk', () async {
    await addRoom('7');
    expect(engine.status.phase, SyncPhase.notConnected);
    expect(engine.active, isFalse);
    await engine.pushNow();
    expect(cloud.tables, isEmpty);
  });

  group('connecting and the first upload', () {
    test('a used or wrong code is refused, and nothing is stored', () async {
      await expectLater(
        engine.connect(
          owner: owner,
          installCode: 'NOPE-NOPE-NOPE',
          ownerEmail: ownerEmail,
          password: testOwner.password,
        ),
        throwsA(isA<CloudRefused>()),
      );
      expect(await secrets.read(), isNull);
      expect(await store.get(SyncStore.deskEmail), isNull);
    });

    test('everything goes up: the cloud row counts match the desk; no '
        'password hash; the owner’s decision and prices through the '
        'owner’s sign-in; the outbox it covered is marked sent', () async {
      await historyWithADecision();
      await connect();

      expect(engine.status.phase, SyncPhase.online);
      expect(engine.active, isTrue);
      expect(await secrets.read(), isNotNull);
      expect(await store.get(SyncStore.ownerEmail), ownerEmail);
      expect(await env.auditFor('sync.connect'), hasLength(1));
      expect(await env.auditFor('sync.first_upload'), hasLength(1));
      await expectCloudMatchesDesk();
      // Seeded rows never went through the outbox, and still arrived.
      expect(cloud.row('bed_categories', SeedIds.vip), isNotNull);
      expect(cloud.row('settings', 'grace_minutes'), isNotNull);
      expect(
        cloud.tables['users']!.values.any(
          (u) => u.containsKey('password_hash'),
        ),
        isFalse,
      );
      expect(cloud.count('refund_decisions'), 1);
      expect(await store.pendingCount(), 0);
      expect(cloud.devices.values.single, isTrue);
    });

    test('interrupted, then resumed after a restart: it carries on from '
        'where it stopped, then waits for the owner to finish', () async {
      await historyWithADecision();
      cloud.goOfflineAfter = 4;
      await connect();
      expect(engine.status.phase, SyncPhase.offline);
      final sentBefore = await store.getInt(SyncStore.uploadSent);
      final total = await store.getInt(SyncStore.uploadTotal);
      expect(sentBefore, greaterThan(0));
      expect(sentBefore, lessThan(total));

      // A power cut: a new engine, no owner signed in to the cloud.
      await engine.dispose();
      cloud
        ..offline = false
        ..goOfflineAfter = null
        ..dropDeskSession();
      await cloud.signOutOwner();
      engine = newEngine();
      await engine.start();
      expect(engine.status.phase, SyncPhase.waitingForOwner);
      expect(engine.status.uploadSent, greaterThanOrEqualTo(sentBefore));

      await engine.ownerSignedInOnDesk(testOwner.password);
      await engine.continueFirstUpload();
      expect(engine.status.phase, SyncPhase.online);
      await expectCloudMatchesDesk();
      // Resumed, not restarted: at most one batch went up twice.
      expect(cloud.importedRows, lessThanOrEqualTo(total + 3));
    });

    test('a write made during the upload still goes up afterwards', () async {
      await historyWithADecision();
      // The network drops early in the upload; back online, the owner has
      // gone, so it pauses after the desk's tables.
      cloud.goOfflineAfter = 1;
      await connect();
      cloud
        ..offline = false
        ..goOfflineAfter = null;
      await engine.ownerLeft();
      await engine.continueFirstUpload();
      expect(engine.status.phase, SyncPhase.waitingForOwner);

      final late = await addRoom('12');
      expect(cloud.row('rooms', late), isNull);
      await engine.ownerSignedInOnDesk(testOwner.password);
      await engine.continueFirstUpload();
      expect(engine.status.phase, SyncPhase.online);
      expect(cloud.row('rooms', late), isNotNull);
      expect(
        cloud.pushes.expand((p) => p).any((r) => r.row['id'] == late),
        isTrue,
        reason: 'it came through the outbox, not the snapshot',
      );
      await expectCloudMatchesDesk();
    });

    test('a missing key (another Windows user): reconnect this desk', () async {
      await connect();
      await engine.dispose();
      secrets.credentials = null;
      cloud.dropDeskSession();
      engine = newEngine();
      await engine.start();
      expect(engine.status.phase, SyncPhase.problem);
      expect(engine.status.needsReconnect, isTrue);

      await engine.reconnect(
        owner: owner,
        ownerEmail: ownerEmail,
        password: testOwner.password,
      );
      expect(engine.status.phase, SyncPhase.online);
      expect(await env.auditFor('sync.reconnect'), hasLength(1));
    });
  });

  group('pushing', () {
    setUp(connect);

    test('in the order written, in batches, each marked sent', () async {
      final rooms = [
        for (final n in ['21', '22', '23']) await addRoom(n),
      ];
      await engine.pushNow();
      expect(engine.status.phase, SyncPhase.online);
      expect(await store.pendingCount(), 0);
      final pushed = [for (final p in cloud.pushes) ...p];
      expect(cloud.pushes.every((p) => p.length <= 3), isTrue);
      final roomOrder = [
        for (final r in pushed)
          if (r.table == 'rooms') r.row['id'],
      ];
      expect(roomOrder, rooms);
      for (final id in rooms) {
        expect(cloud.row('rooms', id), isNotNull);
      }
    });

    test(
      'a lost answer: the batch is sent again, without duplicates',
      () async {
        final room = await addRoom('31');
        cloud.loseNextAnswer = true;
        await engine.pushNow();
        expect(engine.status.phase, SyncPhase.offline);
        expect(cloud.row('rooms', room), isNotNull);
        expect(await store.pendingCount(), greaterThan(0));

        await engine.pushNow();
        expect(engine.status.phase, SyncPhase.online);
        expect(await store.pendingCount(), 0);
        await expectCloudMatchesDesk();
      },
    );

    test(
      'offline: the changes wait, a retry is scheduled, then they go up',
      () async {
        cloud.offline = true;
        await addRoom('41');
        await engine.pushNow();
        expect(engine.status.phase, SyncPhase.offline);
        expect(await store.pendingCount(), greaterThan(0));
        expect(engine.retryAt, isNotNull);

        cloud.offline = false;
        await engine.pushNow();
        expect(engine.status.phase, SyncPhase.online);
        expect(engine.status.lastSyncAt, env.clock.now());
        await expectCloudMatchesDesk();
      },
    );

    test('a refused row stops the queue, with its details, until it goes '
        'through; the heartbeat still reports', () async {
      cloud.refuse = (table, row) =>
          table == 'rooms' && row['room_number'] == '13' ? 'unlucky' : null;
      final thirteen = await addRoom('13');
      final fourteen = await addRoom('14');
      await engine.pushNow();
      expect(engine.status.phase, SyncPhase.problem);
      expect(engine.status.problem, 'rooms $thirteen: unlucky');
      expect(cloud.row('rooms', fourteen), isNull);
      final failed = await (env.db.select(
        env.db.outbox,
      )..where((o) => o.lastError.isNotNull())).getSingle();
      expect((failed.targetRowId, failed.attempts), (thirteen, 1));

      await engine.sendHeartbeat();
      final beat = cloud.heartbeats.last;
      expect(beat.pending, greaterThan(0));
      expect(beat.problem, 'rooms $thirteen: unlucky');

      cloud.refuse = null;
      await engine.pushNow();
      expect(engine.status.phase, SyncPhase.online);
      expect(cloud.row('rooms', fourteen), isNotNull);
    });

    test('sent rows are kept 30 days, unsent ones always', () async {
      await addRoom('51');
      await engine.pushNow();
      cloud.offline = true;
      await addRoom('52');
      env.clock.set(env.clock.now().add(const Duration(days: 31)));
      await engine.prune();
      final left = await env.db.select(env.db.outbox).get();
      expect(left, isNotEmpty);
      expect(left.every((o) => o.sentAt == null), isTrue);
    });
  });

  group('writes that go to the cloud first', () {
    test(
      'need the first upload, the owner’s sign-in and the internet',
      () async {
        Future<void> decide() => engine.decideRefund(
          id: 'd-1',
          refundId: 'r-1',
          approve: true,
          note: null,
          at: env.clock.now(),
        );
        await connect();
        await engine.ownerLeft();
        await expectLater(decide(), throwsA(isA<OwnerCloudSignInNeeded>()));
        await engine.signInOwner(testOwner.password);
        cloud.offline = true;
        await expectLater(decide(), throwsA(isA<NeedsInternet>()));
      },
    );

    test('the first decision wins: decided elsewhere first', () async {
      await historyWithADecision();
      await connect();
      // A second refund, decided on the phone before the desk tries.
      final room = await RoomsRepository(env.db, env.audit).createRoom(
        supervisor,
        const NewRoom(
          number: '8',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: null,
        ),
      );
      final desk = (await env.users.findByUsername('desk'))!.account;
      env.clock.set(nairobiInstant(2026, 10, 16, 19));
      final stay = await env.checkIn(room.beds.single.id, by: desk, nights: 3);
      env.clock.set(nairobiInstant(2026, 10, 17, 10, 30));
      await env.checkOut(stay, by: desk);
      await engine.pushNow();
      final refund = (await (env.db.select(
        env.db.refunds,
      )..where((r) => r.stayId.equals(stay))).getSingle()).id;
      cloud.decideElsewhere(
        'refund_decisions',
        'refund_id',
        refund,
        decision: 'rejected',
        at: nairobiInstant(2026, 10, 17, 10, 42),
      );
      await expectLater(
        engine.decideRefund(
          id: 'd-desk',
          refundId: refund,
          approve: true,
          note: null,
          at: env.clock.now(),
        ),
        throwsA(
          isA<DecidedElsewhere>()
              .having((e) => e.approved, 'approved', isFalse)
              .having((e) => e.at, 'at', nairobiInstant(2026, 10, 17, 10, 42)),
        ),
      );
    });
  });

  test('a row queued before v6 goes up as supervisor, never with its '
      'password hash', () {
    final row = SyncStore.cloudRow('users', {
      'id': 'u1',
      'role': 'admin',
      'password_hash': r'$2b$...',
    }).row;
    expect(row, {'id': 'u1', 'role': 'supervisor'});
  });

  test(
    'the outbox row a mirrored cloud write leaves is already sent',
    () async {
      final id = await addRoom('61');
      await env.audit.writeWithAudit(
        action: 'room.update',
        userId: supervisor.id,
        inCloud: {'rooms'},
        body: (w) => w.update(
          env.db.rooms,
          id,
          const RoomsCompanion(floor: Value('1st')),
        ),
      );
      final rows = await (env.db.select(
        env.db.outbox,
      )..where((o) => o.targetTable.isIn(['rooms', 'audit_log']))).get();
      final room = rows.where((o) => o.targetTable == 'rooms').last;
      final audit = rows.where((o) => o.targetTable == 'audit_log').last;
      expect(room.sentAt, isNotNull);
      expect(audit.sentAt, isNull, reason: 'the audit row is still the desk’s');
    },
  );
}
