import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/sync/cloud.dart';
import 'package:lodging_pos/core/sync/desk_secret_store.dart';
import 'package:lodging_pos/core/sync/pulled_rows.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/core/sync/sync_status_text.dart';
import 'package:lodging_pos/core/sync/sync_store.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/price_requests/data/price_requests_repository.dart';
import 'package:lodging_pos/features/refunds/data/refunds_repository.dart';
import 'package:lodging_pos/features/refunds/domain/refund.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/stays/data/check_in_repository.dart';
import 'package:lodging_pos/features/stays/domain/check_in.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

import '../../helpers/fake_cloud.dart';
import '../../helpers/fixtures.dart';

/// sync-2: the pull of what the owner's side wrote, and the clock check.
void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount supervisor;
  late FakeCloud cloud;
  late MemoryDeskSecretStore secrets;
  late SyncEngine engine;
  late SyncStore store;
  late String refundId;
  late String requestId;

  /// How far the server's clock is ahead of this PC's.
  var serverAhead = Duration.zero;

  SyncEngine newEngine() => SyncEngine(
    db: env.db,
    audit: env.audit,
    cloud: cloud,
    secrets: secrets,
    clock: env.clock,
  );

  setUp(() async {
    serverAhead = Duration.zero;
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19));
    supervisor = await env.createFirstSupervisor(testSetup);
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
    requestId = await PriceRequestsRepository(
      env.db,
      env.audit,
    ).request(supervisor, categoryId: SeedIds.deluxe, newPrice: 750);

    cloud = FakeCloud(serverNow: () => env.clock.now().add(serverAhead));
    secrets = MemoryDeskSecretStore();
    store = SyncStore(env.db);
    engine = newEngine();
    await engine.start();
    await engine.connect(
      owner: owner,
      installCode: 'ABCD-EFGH-JKLM',
      ownerEmail: testOwnerEmail,
      password: testOwner.password,
    );
  });
  tearDown(() async {
    await engine.dispose();
    await env.close();
  });

  Future<int> count(String table) => store.count(table);

  group('the pull', () {
    test(
      'the phone’s rejection and price approval arrive, in order; the '
      'cursor moves to the last one and the next pull starts there',
      () async {
        cloud.decideElsewhere(
          'refund_decisions',
          'refund_id',
          refundId,
          decision: 'rejected',
          note: 'Guest agreed to stay on',
          at: env.clock.now(),
        );
        cloud.decideElsewhere(
          'price_decisions',
          'request_id',
          requestId,
          decision: 'approved',
          at: env.clock.now(),
        );
        await engine.pullNow();

        final refund = await RefundsRepository(
          env.db,
          env.audit,
        ).view(refundId);
        expect(refund.status, RefundStatus.rejected);
        expect(refund.refund.decision!.note, 'Guest agreed to stay on');
        final deluxe = await (env.db.select(
          env.db.bedCategories,
        )..where((c) => c.id.equals(SeedIds.deluxe))).getSingle();
        expect(deluxe.pricePerNight, 750);
        final cursor = await store.getInt(SyncStore.pullAfter);
        expect(cursor, greaterThan(0));

        await engine.pullNow();
        expect(cloud.pulls.last, cursor);
        expect(engine.status.phase, SyncPhase.online);
      },
    );

    test('after a long offline gap it catches up page by page, the cursor '
        'only ever moving forward', () async {
      cloud.offline = true;
      await engine.pullNow();
      final before = cloud.pulls.length;
      for (var i = 0; i < 1200; i++) {
        cloud.phoneAudit('phone-$i', action: 'user.login', at: env.clock.now());
      }
      cloud.offline = false;
      await engine.pullNow();

      final cursors = cloud.pulls.sublist(before);
      expect(cursors, hasLength(3), reason: '500 + 500 + 200 rows');
      for (var i = 1; i < cursors.length; i++) {
        expect(cursors[i], greaterThan(cursors[i - 1]));
      }
      final phoneRows = await (env.db.select(
        env.db.auditLog,
      )..where((a) => a.deviceId.equals('phone'))).get();
      expect(phoneRows, hasLength(1200));
    });

    test(
      'what this desk wrote cloud-first comes back and is skipped',
      () async {
        await RefundsRepository(
          env.db,
          env.audit,
          cloud: engine,
        ).decide(owner, refundId, approve: true);
        await engine.pullNow();
        expect(await count('refund_decisions'), 1);
        expect(engine.status.phase, SyncPhase.online);
      },
    );

    test('pulled rows get no audit or outbox rows and never go back up; '
        'the phone’s own audit rows are kept', () async {
      await engine.syncNow();
      final audit = await count('audit_log');
      final outbox = await count('outbox');
      cloud.decideElsewhere(
        'refund_decisions',
        'refund_id',
        refundId,
        decision: 'approved',
        at: env.clock.now(),
      );
      cloud.phoneAudit(
        'phone-1',
        action: 'refund.approve',
        at: env.clock.now(),
      );
      final pushesBefore = cloud.pushes.length;
      await engine.syncNow();

      expect(await count('refund_decisions'), 1);
      expect(await count('audit_log'), audit + 1, reason: 'the phone’s row');
      expect(await count('outbox'), outbox);
      await engine.syncNow();
      expect(cloud.pushes.length, pushesBefore, reason: 'nothing to push');
    });

    test('a page is applied whole or not at all, and replaying it is '
        'harmless', () async {
      final page = [
        PulledRow('audit_log', 1, {
          ...?cloud.row('audit_log', 'x'),
          'id': 'phone-a',
          'created_at': env.clock.now().toIso8601String(),
          'updated_at': env.clock.now().toIso8601String(),
          'device_id': 'phone',
          'at': env.clock.now().toIso8601String(),
          'operation_id': 'op',
          'user_id': owner.id,
          'action': 'user.login',
          'entity': 'users',
          'entity_id': owner.id,
          'before_json': null,
          'after_json': '{}',
        }),
        const PulledRow('bed_categories', 2, {
          'id': 'no-such-category',
          'price_per_night': 900,
          'price_updated_at': '2026-10-16T08:00:00.000Z',
        }),
      ];
      final rows = PulledRows(env.db, env.clock);
      final cursor = await store.getInt(SyncStore.pullAfter);
      await expectLater(
        rows.apply(page, cursor: 99),
        throwsA(isA<PullConflict>()),
      );
      expect(await store.getInt(SyncStore.pullAfter), cursor);
      expect(
        await (env.db.select(
          env.db.auditLog,
        )..where((a) => a.id.equals('phone-a'))).get(),
        isEmpty,
        reason: 'the audit row went back with the failed page',
      );

      final good = [page.first];
      expect(await rows.apply(good, cursor: 99), 1);
      expect(await rows.apply(good, cursor: 99), 0);
      expect(await store.getInt(SyncStore.pullAfter), 99);
    });

    test('a clashing decision stops the pull with a problem; nothing is '
        'overwritten; the push carries on', () async {
      await RefundsRepository(
        env.db,
        env.audit,
        cloud: engine,
      ).decide(owner, refundId, approve: true);
      // The cloud breaks its own rule: a second decision for the refund.
      cloud.decideElsewhere(
        'refund_decisions',
        'refund_id',
        refundId,
        decision: 'rejected',
        at: env.clock.now(),
      );
      await engine.pullNow();
      expect(engine.status.phase, SyncPhase.problem);
      expect(engine.status.problem, contains('another decision for refund'));
      final local = await env.db.select(env.db.refundDecisions).getSingle();
      expect(local.decision, 'approved');

      final room = await RoomsRepository(env.db, env.audit).createRoom(
        supervisor,
        const NewRoom(
          number: '9',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.vip,
          bedBCategoryId: null,
        ),
      );
      await engine.pushNow();
      expect(cloud.row('rooms', room.id), isNotNull);
      expect(engine.status.phase, SyncPhase.problem, reason: 'still stopped');
    });

    test('the pull carries on while the push queue is stopped', () async {
      cloud.refuse = (table, row) => table == 'rooms' ? 'refused' : null;
      await RoomsRepository(env.db, env.audit).createRoom(
        supervisor,
        const NewRoom(
          number: '13',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.vip,
          bedBCategoryId: null,
        ),
      );
      cloud.decideElsewhere(
        'refund_decisions',
        'refund_id',
        refundId,
        decision: 'approved',
        at: env.clock.now(),
      );
      await engine.syncNow();
      expect(engine.status.phase, SyncPhase.problem);
      expect(
        (await RefundsRepository(env.db, env.audit).view(refundId)).status,
        RefundStatus.approved,
      );
    });

    test('a check-in still showing the old price is refused at save', () async {
      final room = await RoomsRepository(env.db, env.audit).createRoom(
        supervisor,
        const NewRoom(
          number: '6',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: null,
        ),
      );
      final shown = quoteCheckIn(
        checkInAt: env.clock.now(),
        nights: 1,
        checkout: const ClockTime(10, 0),
        beds: [
          LetBed(
            bedId: room.beds.single.id,
            categoryId: SeedIds.deluxe,
            categoryName: 'Deluxe',
            pricePerNight: 700,
          ),
        ],
      );
      cloud.setPriceElsewhere(SeedIds.deluxe, 750, env.clock.now());
      await engine.pullNow();

      final desk = (await env.users.findByUsername('desk'))!.account;
      await expectLater(
        env.checkIns.checkIn(
          desk,
          CheckInRequest(
            guest: NewGuest(
              const GuestForm(
                fullName: 'Mary Wanjiku',
                phone: '0722000310',
                idType: null,
                idNumber: '',
              ),
              phoneSharedWith: const {},
            ),
            method: PaymentMethod.cash,
            mpesaCode: null,
            shown: shown,
          ),
        ),
        throwsA(
          isA<CheckInRefused>().having(
            (e) => e.message,
            'message',
            'Deluxe is now KES 750 a night. Check the total and save again.',
          ),
        ),
      );
    });
  });

  group('the clock check', () {
    Future<void> pullWithServer(Duration ahead) async {
      serverAhead = ahead;
      await engine.pullNow();
    }

    test('warns above 5 minutes either way, slow or fast', () async {
      await pullWithServer(const Duration(minutes: 4, seconds: 59));
      expect(engine.status.clockWarning, isFalse);
      await pullWithServer(const Duration(minutes: 5, seconds: 1));
      expect(engine.status.clockWarning, isTrue);
      expect(
        syncPillText(engine.status, pending: 0, now: env.clock.now()),
        'PC clock 5 min slow · fix',
      );
      expect(
        clockWarningText(engine.status.clockOffset!),
        'PC clock is 5 min slow. Windows Settings → Time & language → '
        'Sync now',
      );

      await pullWithServer(Duration.zero);
      await pullWithServer(-const Duration(minutes: 12));
      expect(engine.status.clockWarning, isTrue);
      expect(clockGap(engine.status.clockOffset!), '12 min fast');
    });

    test('clears only once within 4 minutes; recorded once per episode, '
        'remembered across a restart', () async {
      await pullWithServer(const Duration(minutes: 12));
      await pullWithServer(const Duration(minutes: 4, seconds: 30));
      expect(engine.status.clockWarning, isTrue, reason: 'not yet within 4');
      expect(await env.auditFor('sync.clock_warning'), hasLength(1));

      await engine.dispose();
      cloud.dropDeskSession();
      engine = newEngine();
      await engine.start();
      expect(engine.status.clockWarning, isTrue);
      await pullWithServer(const Duration(minutes: 9));
      expect(await env.auditFor('sync.clock_warning'), hasLength(1));

      await pullWithServer(const Duration(minutes: 3, seconds: 59));
      expect(engine.status.clockWarning, isFalse);
      await pullWithServer(const Duration(minutes: 6));
      expect(await env.auditFor('sync.clock_warning'), hasLength(2));
    });

    test('a slow answer is no measure of the clock', () async {
      cloud.serverNow = () {
        // The answer takes 11 s to come back.
        env.clock.set(env.clock.now().add(const Duration(seconds: 11)));
        return env.clock.now().add(const Duration(hours: 1));
      };
      await engine.pullNow();
      expect(engine.status.clockWarning, isFalse);
      expect(
        engine.status.clockOffset,
        Duration.zero,
        reason: 'the measure from connecting stands',
      );
    });

    test('the heartbeat carries the offset; it warns, never blocks', () async {
      await pullWithServer(const Duration(minutes: 12));
      await engine.sendHeartbeat();
      expect(cloud.heartbeats.last.clockOffsetSeconds, -720);
      expect(engine.status.phase, SyncPhase.online);
      await RefundsRepository(
        env.db,
        env.audit,
        cloud: engine,
      ).decide(owner, refundId, approve: true);
    });
  });
}
