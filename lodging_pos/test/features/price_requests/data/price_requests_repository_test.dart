import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/price_requests/data/price_requests_repository.dart';
import 'package:lodging_pos/features/price_requests/domain/price_request.dart';
import 'package:lodging_pos/features/setup/data/prices_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount supervisor;
  late UserAccount desk;
  late PriceRequestsRepository repo;
  late PricesRepository prices;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 21, 9, 15)); // Wed 09:15
    supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    desk = await env.addReceptionist('desk');
    repo = PriceRequestsRepository(env.db, env.audit);
    prices = PricesRepository(env.db, env.audit);
  });
  tearDown(() => env.close());

  Future<String> askDeluxe({int price = 750, String? reason}) => repo.request(
    supervisor,
    categoryId: SeedIds.deluxe,
    newPrice: price,
    reason: reason,
  );

  Future<int> deluxePrice() async => (await (env.db.select(
    env.db.bedCategories,
  )..where((c) => c.id.equals(SeedIds.deluxe))).getSingle()).pricePerNight;

  Matcher violation(String message) => throwsA(
    isA<PriceRequestRuleViolation>().having(
      (e) => e.message,
      'message',
      message,
    ),
  );

  test('the lifecycle: asked, waiting, approved; the price changes in the '
      'same operation', () async {
    final id = await askDeluxe(reason: 'Others nearby charge 800');
    final asked = (await env.auditFor('price.request')).single;
    expect(asked.userId, supervisor.id);
    expect(jsonDecode(asked.afterJson), containsPair('old_price', 700));

    final waiting = await repo.waiting();
    expect([for (final v in waiting) v.id], [id]);
    expect(waiting.single.categoryName, 'Deluxe');
    expect(waiting.single.requestedByFirstName, 'Grace');
    expect(waiting.single.requestedByRole, Role.supervisor);
    expect(waiting.single.stale, isFalse);

    env.clock.set(nairobiInstant(2026, 10, 21, 10));
    await repo.decide(owner, id, approve: true);
    expect(await deluxePrice(), 750);
    expect((await repo.view(id)).status, PriceRequestStatus.approved);
    expect(await repo.waiting(), isEmpty);

    final approve = (await env.auditFor('price.approve')).single;
    final update = (await env.auditFor('price.update')).single;
    expect(approve.operationId, update.operationId);
    expect((approve.userId, update.userId), (owner.id, owner.id));
    expect(
      jsonDecode(update.beforeJson!),
      containsPair('price_per_night', 700),
    );

    final card = await repo.forSupervisor(env.clock.now());
    expect(card.waiting, isEmpty);
    expect([for (final v in card.recent) v.id], [id]);
    expect(card.recent.single.decidedByName, 'Amina Owner');
  });

  test('reject: a reason is required; the price stays', () async {
    final id = await askDeluxe();
    await expectLater(
      repo.decide(owner, id, approve: false, note: ' '),
      violation('Give a reason for rejecting the price change.'),
    );
    await repo.decide(owner, id, approve: false, note: 'Not this month');
    expect(await deluxePrice(), 700);
    expect(await env.auditFor('price.reject'), hasLength(1));
    expect(await env.auditFor('price.update'), isEmpty);
    final recent = (await repo.forSupervisor(env.clock.now())).recent.single;
    expect(recent.status, PriceRequestStatus.rejected);
    expect(recent.request.decision!.note, 'Not this month');
  });

  test('decided once: the second decision is refused', () async {
    final id = await askDeluxe();
    await repo.decide(owner, id, approve: false, note: 'No');
    await expectLater(
      repo.decide(owner, id, approve: true),
      violation('This request has already been decided.'),
    );
    expect(await deluxePrice(), 700);
  });

  group('one open request per category', () {
    test('a second is refused until the first is answered', () async {
      final first = await askDeluxe();
      await expectLater(
        askDeluxe(price: 800),
        violation('Deluxe already has a request waiting for the owner.'),
      );
      // Another category is separate.
      await repo.request(supervisor, categoryId: SeedIds.vip, newPrice: 1100);
      await repo.decide(owner, first, approve: false, note: 'No');
      await askDeluxe(price: 800);
      expect(await repo.waiting(), hasLength(2));
    });

    test('the database refuses one that skips the rule', () async {
      await askDeluxe();
      await expectLater(
        env.audit.writeWithAudit(
          action: 'price.request',
          userId: supervisor.id,
          body: (w) => w.insert(
            env.db.priceRequests,
            PriceRequestsCompanion.insert(
              categoryId: SeedIds.deluxe,
              oldPrice: 700,
              newPrice: 800,
              requestedBy: supervisor.id,
              requestedAt: w.now,
            ),
          ),
        ),
        throwsA(
          predicate(
            (e) =>
                '$e'.contains('the category already has an open price request'),
          ),
        ),
      );
    });
  });

  group('withdrawing', () {
    test('the supervisor withdraws their own; it disappears', () async {
      final id = await askDeluxe();
      await repo.withdraw(supervisor, id);
      final row = (await env.auditFor('price.request_withdraw')).single;
      expect(row.userId, supervisor.id);
      expect((await repo.view(id)).status, PriceRequestStatus.withdrawn);
      final card = await repo.forSupervisor(env.clock.now());
      expect(card.waiting, isEmpty);
      expect(card.recent, isEmpty);
      // The category is free again.
      await askDeluxe(price: 800);
    });

    test('not once the owner decided; the owner can’t decide a withdrawn '
        'one', () async {
      final decided = await askDeluxe();
      await repo.decide(owner, decided, approve: true);
      await expectLater(
        repo.withdraw(supervisor, decided),
        violation('The owner has already decided this request.'),
      );

      final gone = await askDeluxe(price: 800);
      await repo.withdraw(supervisor, gone);
      await expectLater(
        repo.decide(owner, gone, approve: true),
        violation('This request was withdrawn.'),
      );
    });
  });

  group('closing the category', () {
    test('withdraws its request in the same transaction, by the owner, '
        '“Category closed”; reopened, it starts with none', () async {
      final id = await askDeluxe();
      env.clock.set(nairobiInstant(2026, 10, 21, 11));
      await prices.closeCategory(owner, SeedIds.deluxe);

      final close = (await env.auditFor('category.update')).single;
      final withdraw = (await env.auditFor('price.request_withdraw')).single;
      expect(withdraw.operationId, close.operationId);
      expect(withdraw.userId, owner.id);
      expect(
        jsonDecode(withdraw.afterJson),
        containsPair('withdraw_reason', 'Category closed'),
      );

      final view = await repo.view(id);
      expect(view.status, PriceRequestStatus.withdrawn);
      expect(view.request.withdrawal!.categoryClosed, isTrue);
      expect(view.request.withdrawal!.by, owner.id);
      // The supervisor sees it ("Withdrawn · category closed").
      final card = await repo.forSupervisor(env.clock.now());
      expect([for (final v in card.recent) v.id], [id]);

      await prices.reopenCategory(owner, SeedIds.deluxe);
      expect(await repo.waiting(), isEmpty);
      await askDeluxe(price: 800);
    });

    test('a closed category can’t be asked about', () async {
      await prices.closeCategory(owner, SeedIds.deluxe);
      expect(await env.auditFor('price.request_withdraw'), isEmpty);
      await expectLater(askDeluxe(), violation('Deluxe is closed.'));
    });
  });

  test('stale: the owner changed the price directly; approval is refused, '
      'rejecting still works', () async {
    final id = await askDeluxe();
    await prices.savePrices(owner, {SeedIds.deluxe: 720});
    final view = await repo.view(id);
    expect((view.stale, view.currentPrice), (true, 720));
    await expectLater(
      repo.decide(owner, id, approve: true),
      throwsA(
        isA<StalePriceRequest>().having(
          (e) => e.message,
          'message',
          'Deluxe is now KES 720, not 700. Reject this request or ask for a '
              'new one.',
        ),
      ),
    );
    expect(await deluxePrice(), 720);
    expect(await env.auditFor('price.approve'), isEmpty);
    await repo.decide(owner, id, approve: false, note: 'Already changed');
  });

  test('the new price: the owner’s rule, and not today’s price', () async {
    await expectLater(
      askDeluxe(price: 0),
      throwsA(isA<InvalidRequestedPrice>()),
    );
    await expectLater(
      askDeluxe(price: 700),
      throwsA(
        isA<InvalidRequestedPrice>().having(
          (e) => e.message,
          'message',
          'That’s already the price.',
        ),
      ),
    );
    expect(await env.auditFor('price.request'), isEmpty);
  });

  test('permissions: the supervisor asks, the owner decides, the desk does '
      'neither', () async {
    await expectLater(
      repo.request(owner, categoryId: SeedIds.deluxe, newPrice: 750),
      throwsA(isA<NotPermitted>()),
    );
    await expectLater(
      repo.request(desk, categoryId: SeedIds.deluxe, newPrice: 750),
      throwsA(isA<NotPermitted>()),
    );
    final id = await askDeluxe();
    for (final user in [supervisor, desk]) {
      await expectLater(
        repo.decide(user, id, approve: true),
        throwsA(isA<NotPermitted>()),
      );
    }
    await expectLater(repo.withdraw(desk, id), throwsA(isA<NotPermitted>()));
    await expectLater(repo.withdraw(owner, id), throwsA(isA<NotPermitted>()));
    expect(await deluxePrice(), 700);
  });

  test('BR-3: a stay already in keeps its price; the next check-in pays the '
      'new one', () async {
    final room = await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '5',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: SeedIds.deluxe,
      ),
    );
    final before = await env.checkIn(room.beds.first.id, by: desk, nights: 2);
    await repo.decide(owner, await askDeluxe(), approve: true);
    final after = await env.checkIn(room.beds.last.id, by: desk, nights: 2);

    Future<int> chargedFor(String stayId) async => (await (env.db.select(
      env.db.stayCharges,
    )..where((c) => c.stayId.equals(stayId))).getSingle()).pricePerNight;
    expect(await chargedFor(before), 700);
    expect(await chargedFor(after), 750);
  });

  test('the supervisor’s card keeps answers for 14 days', () async {
    final id = await askDeluxe();
    await repo.decide(owner, id, approve: false, note: 'No');
    env.clock.set(nairobiInstant(2026, 11, 4, 9));
    expect((await repo.forSupervisor(env.clock.now())).recent, hasLength(1));
    env.clock.set(nairobiInstant(2026, 11, 4, 9, 16));
    expect((await repo.forSupervisor(env.clock.now())).recent, isEmpty);
  });
}
