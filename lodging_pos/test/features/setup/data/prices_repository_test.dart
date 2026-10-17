import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/prices_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/prices_settings.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late PricesRepository prices;
  late UserAccount owner;
  late UserAccount desk;

  setUp(() async {
    env = TestEnv();
    prices = PricesRepository(env.db, env.audit);
    owner = await env.users.createFirstAdmin(testSetup);
    desk = await env.addReceptionist('desk');
  });
  tearDown(() => env.close());

  Future<Map<String, int>> priceById() async => {
    for (final u in await prices.categories())
      u.category.id: u.category.pricePerNight,
  };

  Map<String, Object?> json(String text) =>
      jsonDecode(text) as Map<String, Object?>;

  group('prices', () {
    test('saves only changed prices, one price.update row each with old and '
        'new', () async {
      final changed = await prices.savePrices(owner, {
        SeedIds.deluxe: 750,
        SeedIds.vip: 1000, // unchanged
        SeedIds.normal: 550,
      });
      expect(changed, 2);
      final now = await priceById();
      expect(
        (now[SeedIds.deluxe], now[SeedIds.vip], now[SeedIds.normal]),
        (750, 1000, 550),
      );

      final audit =
          await (env.db.select(env.db.auditLog)
                ..where((a) => a.action.equals('price.update'))
                ..orderBy([(a) => OrderingTerm.asc(a.at)]))
              .get();
      expect(audit, hasLength(2));
      final deluxe = audit.firstWhere((a) => a.entityId == SeedIds.deluxe);
      expect(json(deluxe.beforeJson!)['price_per_night'], 700);
      expect(json(deluxe.afterJson)['price_per_night'], 750);
      expect(deluxe.userId, owner.id);
      expect(audit.map((a) => a.operationId).toSet(), hasLength(1));
    });

    test('nothing changed, nothing written', () async {
      expect(await prices.savePrices(owner, {SeedIds.vip: 1000}), 0);
      expect(await env.auditFor('price.update'), isEmpty);
    });

    test('prices outside 1–100,000 are refused per category', () async {
      await expectLater(
        prices.savePrices(owner, {SeedIds.vip: 0, SeedIds.deluxe: 100001}),
        throwsA(
          isA<InvalidPrices>().having((e) => e.errors, 'errors', {
            SeedIds.vip: 'The price must be at least KES 1.',
            SeedIds.deluxe: 'The price can be at most KES 100,000.',
          }),
        ),
      );
      expect((await priceById())[SeedIds.vip], 1000);
    });

    test('a receptionist cannot change prices or categories', () async {
      for (final attempt in [
        () => prices.savePrices(desk, {SeedIds.vip: 900}),
        () => prices.addCategory(desk, name: 'Family', pricePerNight: 900),
        () => prices.closeCategory(desk, SeedIds.vip),
      ]) {
        await expectLater(
          attempt(),
          throwsA(
            isA<NotPermitted>().having(
              (e) => e.permission,
              'permission',
              Permission.editPrices,
            ),
          ),
        );
      }
      expect((await priceById())[SeedIds.vip], 1000);
    });

    test('a stay keeps its check-in price after a change (BR-3)', () async {
      final room = await RoomsRepository(env.db, env.audit).createRoom(
        owner,
        const NewRoom(
          number: '3',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: null,
        ),
      );
      await env.checkIn(room.beds.single.id, by: owner);
      await prices.savePrices(owner, {SeedIds.deluxe: 750});
      final charge = await env.db.select(env.db.stayCharges).getSingle();
      expect(charge.pricePerNight, 700);
    });
  });

  group('categories', () {
    test('adds a category at the end, trimmed (category.create)', () async {
      final added = await prices.addCategory(
        owner,
        name: '  Family ',
        pricePerNight: 900,
      );
      expect(
        (added.name, added.pricePerNight, added.isActive),
        ('Family', 900, true),
      );
      final all = await prices.categories();
      expect(all.last.category.name, 'Family');
      expect(all.last.activeBeds, 0);
      expect(await env.auditFor('category.create'), hasLength(1));
    });

    test('a name in use (any case) or a bad price is refused', () async {
      await expectLater(
        prices.addCategory(owner, name: 'deluxe', pricePerNight: 900),
        throwsA(
          isA<CategoryRuleViolation>().having(
            (e) => e.message,
            'message',
            'Deluxe already exists.',
          ),
        ),
      );
      await expectLater(
        prices.addCategory(owner, name: 'Family', pricePerNight: 0),
        throwsA(isA<CategoryRuleViolation>()),
      );
    });

    test('counts active beds, including in a closed room; cannot close a '
        'category they use', () async {
      final rooms = RoomsRepository(env.db, env.audit);
      final room = await rooms.createRoom(
        owner,
        const NewRoom(
          number: '3',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: SeedIds.deluxe,
        ),
      );
      await rooms.deactivateRoom(owner, room.id);

      final deluxe = (await prices.categories()).firstWhere(
        (u) => u.category.id == SeedIds.deluxe,
      );
      expect(deluxe.activeBeds, 2);
      await expectLater(
        prices.closeCategory(owner, SeedIds.deluxe),
        throwsA(
          isA<CategoryRuleViolation>().having(
            (e) => e.message,
            'message',
            '2 beds use Deluxe. Move them to another category first.',
          ),
        ),
      );
    });

    test('close and reopen an unused category (category.update)', () async {
      await prices.closeCategory(owner, SeedIds.vip);
      var vip = (await prices.categories()).first.category;
      expect(vip.isActive, isFalse);
      await prices.reopenCategory(owner, SeedIds.vip);
      vip = (await prices.categories()).first.category;
      expect(vip.isActive, isTrue);

      final audit = await env.auditFor('category.update');
      expect(audit, hasLength(2));
      expect([
        for (final a in audit) json(a.afterJson)['is_active'],
      ], unorderedEquals([false, true]));
    });
  });

  group('settings', () {
    test('loads the seeded values', () async {
      final s = await prices.settings();
      expect(s.lodgingName, testSetup.lodgingName);
      expect(s.checkoutTime, const ClockTime(10, 0));
      expect(
        (s.graceMinutes, s.idleLockMinutes, s.receiptPrefix),
        ('60', '10', 'R'),
      );
      expect(await prices.nextReceiptNumber(), 1);
    });

    test('saves changed keys only, one settings.update row each with old and '
        'new', () async {
      final current = await prices.settings();
      final changed = await prices.saveSettings(
        owner,
        SettingsInput(
          lodgingName: current.lodgingName,
          checkoutTime: const ClockTime(9, 30),
          graceMinutes: '45',
          idleLockMinutes: current.idleLockMinutes,
          receiptPrefix: 'sun',
        ),
      );
      expect(changed, 3);
      final s = await prices.settings();
      expect(s.checkoutTime, const ClockTime(9, 30));
      expect((s.graceMinutes, s.receiptPrefix), ('45', 'SUN'));

      final audit = (await env.auditFor('settings.update'))
          .where((a) => a.userId == owner.id && a.entityId != 'lodging_name')
          .toList();
      expect(audit, hasLength(3));
      final grace = audit.firstWhere((a) => a.entityId == 'grace_minutes');
      expect(json(grace.beforeJson!)['value'], '60');
      expect(json(grace.afterJson)['value'], '45');
      expect(json(grace.afterJson)['updated_by'], owner.id);
    });

    test('an invalid form is refused with every field error', () async {
      await expectLater(
        prices.saveSettings(
          owner,
          const SettingsInput(
            lodgingName: ' ',
            checkoutTime: ClockTime(15, 0),
            graceMinutes: '181',
            idleLockMinutes: '61',
            receiptPrefix: 'R1',
          ),
        ),
        throwsA(
          isA<InvalidSettings>().having(
            (e) => e.errors.keys.toSet(),
            'fields',
            SettingsField.values.toSet(),
          ),
        ),
      );
    });

    test('a receptionist cannot change settings', () async {
      await expectLater(
        prices.saveSettings(desk, await prices.settings()),
        throwsA(
          isA<NotPermitted>().having(
            (e) => e.permission,
            'permission',
            Permission.editSettings,
          ),
        ),
      );
    });
  });
}
