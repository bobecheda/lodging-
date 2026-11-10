import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/drawer_repository.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/shifts/domain/drawer.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount supervisor;
  late UserAccount mary;
  late DrawerRepository drawer;
  late ShiftRepository shifts;
  late String shiftId;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 11, 16, 8));
    supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    mary = await env.addReceptionist('mary');
    shifts = ShiftRepository(env.db, env.audit);
    drawer = DrawerRepository(env.db, env.audit, env.hasher, env.clock);
    // Starting cash 2,000; Mary opens; KES 700 cash at 09:00.
    shiftId = (await env.openShift(mary, startingCash: 2000)).id;
    final room = await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '4',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    env.clock.set(nairobiInstant(2026, 11, 16, 9));
    await env.checkIn(room.beds.single.id, by: mary);
    env.clock.set(nairobiInstant(2026, 11, 16, 12));
  });
  tearDown(() => env.close());

  Future<CosignToken> cosign(UserAccount by) =>
      drawer.cosign(by, presentUserId: mary.id, password: 'desk-pass');

  Future<List<DrawerEventRow>> counts() => (env.db.select(
    env.db.drawerEvents,
  )..where((d) => d.kind.isNotValue('start'))).get();

  group('who is present: the receptionist co-signs', () {
    test(
      'the receptionist on shift co-signs with their own password',
      () async {
        expect((await drawer.presentForCount())?.id, mary.id);
        final token = await cosign(supervisor);
        expect(token.presentUserId, mary.id);
      },
    );

    test(
      'a wrong password is refused and audited, and gives no token',
      () async {
        await expectLater(
          drawer.cosign(
            supervisor,
            presentUserId: mary.id,
            password: testOwner.password, // not Mary's
          ),
          throwsA(
            isA<CosignRefused>().having(
              (e) => e.message,
              'message',
              'That password isn’t right.',
            ),
          ),
        );
        final failed = (await env.auditFor('drawer.cosign_failed')).single;
        expect((failed.userId, failed.entityId), (supervisor.id, mary.id));
      },
    );

    test('the counter can’t co-sign as the one present', () async {
      await expectLater(
        drawer.cosign(
          supervisor,
          presentUserId: supervisor.id,
          password: testSetup.password,
        ),
        throwsA(isA<CosignRefused>()),
      );
    });

    test('with a shift open, only its receptionist co-signs', () async {
      final tom = await env.addReceptionist('tom');
      await expectLater(
        drawer.cosign(supervisor, presentUserId: tom.id, password: 'desk-pass'),
        throwsA(isA<CosignRefused>()),
      );
    });

    test('a receptionist can’t count the drawer at all', () async {
      final tom = await env.addReceptionist('tom');
      await expectLater(
        drawer.cosign(tom, presentUserId: mary.id, password: 'desk-pass'),
        throwsA(isA<NotPermitted>()),
      );
    });

    test('a token is used once, by the one it was given to', () async {
      final token = await cosign(supervisor);
      await drawer.recordCount(
        supervisor,
        token,
        kind: DrawerCountKind.check,
        firstCount: 2700,
      );
      await expectLater(
        drawer.recordCount(
          supervisor,
          token,
          kind: DrawerCountKind.check,
          firstCount: 2700,
        ),
        throwsA(isA<CosignRefused>()),
      );
      final other = await cosign(supervisor);
      await expectLater(
        drawer.recordCount(
          owner,
          other,
          kind: DrawerCountKind.check,
          firstCount: 2700,
        ),
        throwsA(isA<CosignRefused>()),
      );
    });
  });

  group('a drawer check (drawer.check)', () {
    test('matches: recorded, both names, no review; a new anchor', () async {
      final row = await drawer.recordCount(
        supervisor,
        await cosign(supervisor),
        kind: DrawerCountKind.check,
        firstCount: 2700,
      );
      expect(
        (row.kind, row.expected, row.counted, row.needsReview),
        ('check', 2700, 2700, false),
      );
      expect(
        (row.countedBy, row.presentUser, row.shiftId),
        (supervisor.id, mary.id, shiftId),
      );
      final audit = (await env.auditFor('drawer.check')).single;
      expect(audit.userId, supervisor.id);
    });

    test('a first count that misses is audited; one recount; then a '
        'reason; recorded needing review, and in the chain', () async {
      final token = await cosign(owner);
      expect(await drawer.firstCountMatches(owner, token, 2600), isFalse);
      expect(await env.auditFor('drawer.count_mismatch'), hasLength(1));
      await expectLater(
        drawer.recordCount(
          owner,
          token,
          kind: DrawerCountKind.check,
          firstCount: 2600,
          recount: 2650,
        ),
        throwsA(isA<DrawerCountProblem>()),
      );
      final row = await drawer.recordCount(
        owner,
        token,
        kind: DrawerCountKind.check,
        firstCount: 2600,
        recount: 2650,
        note: 'Mary says a guest was given too much change',
      );
      expect(
        (row.firstCount, row.counted, row.expected, row.needsReview),
        (2600, 2650, 2700, true),
      );
      final check = (await shifts.drawerChain(owner))
          .whereType<DrawerChecked>()
          .single;
      expect((check.gap, check.needsReview), (-50, true));
    });

    test('a third count: a recount after a matching first count is '
        'refused', () async {
      await expectLater(
        drawer.recordCount(
          supervisor,
          await cosign(supervisor),
          kind: DrawerCountKind.check,
          firstCount: 2700,
          recount: 2650,
        ),
        throwsA(isA<DrawerCountProblem>()),
      );
      expect(await counts(), isEmpty);
    });

    test('negative counts are refused', () async {
      await expectLater(
        drawer.recordCount(
          supervisor,
          await cosign(supervisor),
          kind: DrawerCountKind.check,
          firstCount: -1,
        ),
        throwsA(isA<DrawerCountProblem>()),
      );
    });

    test('later cash adds to the check’s count; the close is counted '
        'against it', () async {
      await drawer.recordCount(
        owner,
        await cosign(owner),
        kind: DrawerCountKind.check,
        firstCount: 2600,
        recount: 2600,
        note: 'Short at the check',
      );
      // Another KES 700 after the check: the drawer should hold 3,300.
      env.clock.set(nairobiInstant(2026, 11, 16, 13));
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
      await env.checkIn(room.beds.single.id, by: mary);
      env.clock.set(nairobiInstant(2026, 11, 16, 20));
      expect(await shifts.drawerNow(owner), 3300);
      expect(await shifts.submitCount(mary, shiftId, 3300), isA<CountClosed>());
    });
  });

  group('a collection (drawer.collect)', () {
    test('counted, then what is taken; the next float follows', () async {
      final row = await drawer.recordCount(
        owner,
        await cosign(owner),
        kind: DrawerCountKind.collect,
        firstCount: 2700,
        removed: 2500,
      );
      expect((row.kind, row.counted, row.removed), ('collect', 2700, 2500));
      expect((await env.auditFor('drawer.collect')).single.userId, owner.id);
      expect(await shifts.drawerNow(owner), 200);
      await shifts.submitCount(mary, shiftId, 200);
      env.clock.set(nairobiInstant(2026, 11, 17, 8));
      expect((await shifts.openShift(user: mary)).openingFloat, 200);
    });

    test('more than counted, or a negative amount, is refused', () async {
      for (final removed in [2701, -1]) {
        await expectLater(
          drawer.recordCount(
            owner,
            await cosign(owner),
            kind: DrawerCountKind.collect,
            firstCount: 2700,
            removed: removed,
          ),
          throwsA(isA<DrawerRefused>()),
          reason: '$removed',
        );
      }
      expect(await counts(), isEmpty);
    });

    test('a receptionist can’t collect, even with a token', () async {
      final token = await cosign(supervisor);
      await expectLater(
        drawer.recordCount(
          mary,
          token,
          kind: DrawerCountKind.collect,
          firstCount: 2700,
          removed: 2700,
        ),
        throwsA(isA<NotPermitted>()),
      );
      expect(can(mary, Permission.collectCash), isFalse);
    });

    test('a check takes nothing away', () async {
      await expectLater(
        drawer.recordCount(
          supervisor,
          await cosign(supervisor),
          kind: DrawerCountKind.check,
          firstCount: 2700,
          removed: 100,
        ),
        throwsA(isA<DrawerRefused>()),
      );
    });
  });

  group('with no shift open', () {
    setUp(() async {
      await shifts.submitCount(mary, shiftId, 2700);
    });

    test('a receptionist is picked and co-signs; no shift recorded', () async {
      expect(await drawer.presentForCount(), isNull);
      expect([
        for (final u in await drawer.peopleWhoMayBePresent(owner)) u.id,
      ], contains(mary.id));
      final row = await drawer.recordCount(
        owner,
        await cosign(owner),
        kind: DrawerCountKind.collect,
        firstCount: 2700,
        removed: 2000,
      );
      expect((row.shiftId, row.presentUser), (null, mary.id));
    });
  });
}
