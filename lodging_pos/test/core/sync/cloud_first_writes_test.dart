import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/sync/cloud_writes.dart';
import 'package:lodging_pos/core/sync/desk_secret_store.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/features/price_requests/data/price_requests_repository.dart';
import 'package:lodging_pos/features/price_requests/domain/price_request.dart';
import 'package:lodging_pos/features/refunds/data/refunds_repository.dart';
import 'package:lodging_pos/features/refunds/domain/refund.dart';
import 'package:lodging_pos/features/setup/data/prices_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../helpers/fake_cloud.dart';
import '../../helpers/fixtures.dart';

/// The owner's decisions and prices, and price request withdrawals, once
/// the desk is connected: the cloud first (the first write anywhere wins),
/// then the same row here, its outbox row already sent.
void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount supervisor;
  late FakeCloud cloud;
  late SyncEngine engine;
  late RefundsRepository refunds;
  late PriceRequestsRepository requests;
  late PricesRepository prices;
  late String refundId;

  setUp(() async {
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

    cloud = FakeCloud(serverNow: () => env.clock.now());
    engine = SyncEngine(
      db: env.db,
      audit: env.audit,
      cloud: cloud,
      secrets: MemoryDeskSecretStore(),
      clock: env.clock,
    );
    await engine.start();
    await engine.connect(
      owner: owner,
      installCode: 'ABCD-EFGH-JKLM',
      ownerEmail: testOwnerEmail,
      password: testOwner.password,
    );
    refunds = RefundsRepository(env.db, env.audit, cloud: engine);
    requests = PriceRequestsRepository(env.db, env.audit, cloud: engine);
    prices = PricesRepository(env.db, env.audit, cloud: engine);
  });
  tearDown(() async {
    await engine.dispose();
    await env.close();
  });

  Future<int> localPrice(String categoryId) async => (await (env.db.select(
    env.db.bedCategories,
  )..where((c) => c.id.equals(categoryId))).getSingle()).pricePerNight;

  Future<int> audited(String action) async => (await (env.db.select(
    env.db.auditLog,
  )..where((a) => a.action.equals(action))).get()).length;

  Matcher refundRule(String message) => throwsA(
    isA<RefundRuleViolation>().having((e) => e.message, 'message', message),
  );

  Future<bool> outboxSent(String table, String id) async {
    final row =
        await (env.db.select(env.db.outbox)..where(
              (o) => o.targetTable.equals(table) & o.targetRowId.equals(id),
            ))
            .get();
    return row.last.sentAt != null;
  }

  group('refunds', () {
    test('approved in the cloud first, then here with the same id; its '
        'outbox row already sent, its audit row still going up', () async {
      await refunds.decide(owner, refundId, approve: true);
      final local = await env.db.select(env.db.refundDecisions).getSingle();
      expect(cloud.row('refund_decisions', local.id), isNotNull);
      expect(
        cloud.row('refund_decisions', local.id)!['decided_at'],
        local.decidedAt.toIso8601String(),
      );
      expect(await outboxSent('refund_decisions', local.id), isTrue);
      expect((await refunds.view(refundId)).status, RefundStatus.approved);
      await engine.pushNow();
      expect(engine.status.phase, SyncPhase.online);
    });

    test('offline: "Approving needs an internet connection." and nothing '
        'changes here', () async {
      cloud.offline = true;
      await expectLater(
        refunds.decide(owner, refundId, approve: true),
        refundRule('Approving needs an internet connection.'),
      );
      await expectLater(
        refunds.decide(owner, refundId, approve: false, note: 'No'),
        refundRule('Rejecting needs an internet connection.'),
      );
      expect(await env.db.select(env.db.refundDecisions).get(), isEmpty);
    });

    test('decided on the phone first: the desk is told who and when', () async {
      cloud.decideElsewhere(
        'refund_decisions',
        'refund_id',
        refundId,
        decision: 'rejected',
        at: nairobiInstant(2026, 10, 16, 10, 42),
      );
      await expectLater(
        refunds.decide(owner, refundId, approve: true),
        refundRule(
          'Already decided by Amina Owner · Fri 16 Oct, 10:42 (rejected).',
        ),
      );
      expect(await env.db.select(env.db.refundDecisions).get(), isEmpty);
    });

    test(
      'without the owner’s cloud sign-in the screen is asked for it',
      () async {
        await engine.ownerLeft();
        await expectLater(
          refunds.decide(owner, refundId, approve: true),
          throwsA(isA<OwnerCloudSignInNeeded>()),
        );
        await engine.signInOwner(testOwner.password);
        await refunds.decide(owner, refundId, approve: true);
        expect((await refunds.view(refundId)).status, RefundStatus.approved);
      },
    );
  });

  group('price requests and prices', () {
    late String requestId;
    setUp(() async {
      requestId = await requests.request(
        supervisor,
        categoryId: SeedIds.deluxe,
        newPrice: 750,
      );
    });

    test('approved in the cloud first: both prices are 750; the decision '
        'and the price rows already sent', () async {
      await requests.decide(owner, requestId, approve: true);
      expect(
        cloud.row('bed_categories', SeedIds.deluxe)!['price_per_night'],
        750,
      );
      final local = await env.db.select(env.db.priceDecisions).getSingle();
      expect(cloud.row('price_decisions', local.id), isNotNull);
      expect(await outboxSent('price_decisions', local.id), isTrue);
      expect(await outboxSent('bed_categories', SeedIds.deluxe), isTrue);
      final deluxe = await (env.db.select(
        env.db.bedCategories,
      )..where((c) => c.id.equals(SeedIds.deluxe))).getSingle();
      expect(deluxe.pricePerNight, 750);
    });

    test('the cloud’s price moved on (edited on the phone): refused as '
        'stale with the cloud’s price', () async {
      await engine.pushNow();
      cloud.row('bed_categories', SeedIds.deluxe)!['price_per_night'] = 720;
      await expectLater(
        requests.decide(owner, requestId, approve: true),
        throwsA(
          isA<StalePriceRequest>().having(
            (e) => e.message,
            'message',
            'Deluxe is now KES 720, not 700. Reject this request or ask for '
                'a new one.',
          ),
        ),
      );
    });

    test(
      'the supervisor’s withdrawal loses to a decision made first',
      () async {
        await engine.pushNow();
        cloud.decideElsewhere(
          'price_decisions',
          'request_id',
          requestId,
          decision: 'approved',
          at: env.clock.now(),
        );
        await expectLater(
          requests.withdraw(supervisor, requestId),
          throwsA(
            isA<PriceRequestRuleViolation>().having(
              (e) => e.message,
              'message',
              'The owner has already decided this request.',
            ),
          ),
        );
      },
    );

    test('withdrawn in the cloud first', () async {
      await requests.withdraw(supervisor, requestId);
      expect(
        cloud.row('price_requests', requestId)!['withdrawn_by'],
        supervisor.id,
      );
      expect(await outboxSent('price_requests', requestId), isTrue);
      expect(
        (await requests.view(requestId)).status,
        PriceRequestStatus.withdrawn,
      );
    });

    test('closing the category withdraws its request in the cloud first; '
        'offline, the close is refused and nothing changes', () async {
      // Comfort has no beds, so only the withdrawal can stop the close.
      requestId = await requests.request(
        supervisor,
        categoryId: SeedIds.comfort,
        newPrice: 650,
      );
      cloud.offline = true;
      await expectLater(
        prices.closeCategory(owner, SeedIds.comfort),
        throwsA(
          isA<CategoryRuleViolation>().having(
            (e) => e.message,
            'message',
            'Closing Comfort withdraws its price request, which needs an '
                'internet connection.',
          ),
        ),
      );
      expect(
        (await requests.view(requestId)).status,
        PriceRequestStatus.waiting,
      );

      cloud.offline = false;
      await prices.closeCategory(owner, SeedIds.comfort);
      final inCloud = cloud.row('price_requests', requestId)!;
      expect(
        (inCloud['withdrawn_by'], inCloud['withdraw_reason']),
        (owner.id, 'Category closed'),
      );
      expect(
        (await requests.view(requestId)).status,
        PriceRequestStatus.withdrawn,
      );
    });

    test('prices: set in the cloud first; offline, refused', () async {
      cloud.offline = true;
      await expectLater(
        prices.savePrices(owner, {SeedIds.vip: 1100}),
        throwsA(
          isA<CategoryRuleViolation>().having(
            (e) => e.message,
            'message',
            'Changing prices needs an internet connection.',
          ),
        ),
      );
      // Nothing was saved here first.
      expect(await localPrice(SeedIds.vip), 1000);
      expect(await audited('price.update'), 0);

      cloud.offline = false;
      await prices.savePrices(owner, {SeedIds.vip: 1100});
      expect(
        cloud.row('bed_categories', SeedIds.vip)!['price_per_night'],
        1100,
      );
      expect(await outboxSent('bed_categories', SeedIds.vip), isTrue);
    });

    test('prices: an edit made on the phone first wins; the desk is told '
        'where and saves nothing', () async {
      final atPhone = nairobiInstant(2026, 10, 16, 10, 40);
      cloud.setPriceElsewhere(SeedIds.vip, 1200, atPhone);
      // Not pulled yet: the desk still thinks VIP is 1,000.
      await expectLater(
        prices.savePrices(owner, {SeedIds.vip: 1100, SeedIds.deluxe: 750}),
        throwsA(
          isA<CategoryRuleViolation>().having(
            (e) => e.message,
            'message',
            'VIP was changed to KES 1,200 on the phone · Fri 16 Oct, 10:40. '
                'Check it and save again.',
          ),
        ),
      );
      expect(
        cloud.row('bed_categories', SeedIds.vip)!['price_per_night'],
        1200,
      );
      // All or nothing: Deluxe wasn't changed either, here or there.
      expect(
        cloud.row('bed_categories', SeedIds.deluxe)!['price_per_night'],
        700,
      );
      expect(await localPrice(SeedIds.deluxe), 700);
      expect(await audited('price.update'), 0);
    });
  });
}
