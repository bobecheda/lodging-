import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/housekeeping/data/housekeeping_repository.dart';
import 'package:lodging_pos/features/housekeeping/domain/housekeeping.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/data/staff_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late UserAccount desk;
  late HousekeepingRepository repo;
  late RoomsRepository rooms;
  late StaffRepository staff;
  late RoomSummary r7;
  late String rose;
  late String jane;
  late String bedA;
  late String bedB;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19));
    supervisor = await env.users.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('mary');
    repo = HousekeepingRepository(env.db, env.audit);
    rooms = RoomsRepository(env.db, env.audit);
    staff = StaffRepository(env.db, env.audit, env.hasher);
    r7 = await rooms.createRoom(
      supervisor,
      const NewRoom(
        number: '7',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: SeedIds.comfort,
      ),
    );
    bedA = r7.beds.first.id;
    bedB = r7.beds.last.id;
    rose = (await staff.addHousekeeper(
      supervisor,
      name: 'Rose Akinyi',
      phone: '',
    )).id;
    jane = (await staff.addHousekeeper(
      supervisor,
      name: 'Jane Wanjiru',
      phone: '',
    )).id;
    // Bed A: a guest stayed one night and left (BR-9: not cleaned).
    final stay = await env.checkIn(bedA, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 9, 30));
    await env.checkOut(stay, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 11, 40));
  });
  tearDown(() => env.close());

  Future<BedRow> bed(String id) =>
      (env.db.select(env.db.beds)..where((b) => b.id.equals(id))).getSingle();

  Future<List<HousekeepingTaskRow>> tasks() =>
      env.db.select(env.db.housekeepingTasks).get();

  test('the panel’s view: not cleaned, last checkout, nobody yet', () async {
    final b = await repo.watchBed(bedA).first;
    expect((b.roomNumber, b.label), ('7', BedLabel.a));
    expect(b.cleanliness, Cleanliness.notCleaned);
    expect(b.lastCheckoutAt, nairobiInstant(2026, 10, 16, 9, 30));
    expect(b.openTask, isNull);
  });

  group('assign (housekeeping.assign)', () {
    test(
      'records who, when and by whom; the panel shows the first name',
      () async {
        await repo.assign(desk, bedA, rose);
        final task = (await tasks()).single;
        expect((task.bedId, task.housekeeperId), (bedA, rose));
        expect((task.assignedBy, task.assignedAt), (desk.id, env.clock.now()));
        expect(task.completedAt, isNull);
        final b = await repo.watchBed(bedA).first;
        expect(b.openTask!.housekeeperName, 'Rose');
        expect(
          (await env.auditFor('housekeeping.assign')).single.entity,
          'housekeeping_tasks',
        );
        // Still not clean until marked.
        expect((await bed(bedA)).cleanliness, 'not_cleaned');
      },
    );

    test('refused: a clean bed, a bed already given, an inactive '
        'housekeeper', () async {
      await expectLater(
        repo.assign(desk, bedB, rose),
        throwsA(isA<HousekeepingRefused>()),
      );
      await repo.assign(desk, bedA, rose);
      await expectLater(
        repo.assign(desk, bedA, jane),
        throwsA(
          isA<HousekeepingRefused>().having(
            (e) => e.message,
            'message',
            'Someone is already cleaning this bed. Reassign it instead.',
          ),
        ),
      );
      expect(await tasks(), hasLength(1));
    });
  });

  group('mark clean (bed.mark_clean)', () {
    test(
      'completes the task and makes the bed clean, in one operation',
      () async {
        await repo.assign(desk, bedA, rose);
        env.clock.set(nairobiInstant(2026, 10, 16, 12, 15));
        await repo.markClean(desk, bedA);
        final task = (await tasks()).single;
        expect(
          (task.completedAt, task.completedBy),
          (env.clock.now(), desk.id),
        );
        expect((await bed(bedA)).cleanliness, 'clean');
        final audit = await env.auditFor('bed.mark_clean');
        expect(
          {for (final a in audit) a.entity},
          {'housekeeping_tasks', 'beds'},
        );
        expect({for (final a in audit) a.operationId}, hasLength(1));
        expect((await repo.watchBed(bedA).first).openTask, isNull);
      },
    );

    test('BR-9: no task, no mark clean', () async {
      await expectLater(
        repo.markClean(desk, bedA),
        throwsA(isA<HousekeepingRefused>()),
      );
      expect((await bed(bedA)).cleanliness, 'not_cleaned');
    });
  });

  test(
    '"Already cleaned": a task created and completed in one operation',
    () async {
      await repo.cleanNow(desk, bedA, jane);
      final task = (await tasks()).single;
      expect(task.housekeeperId, jane);
      expect(task.completedAt, env.clock.now());
      expect((await bed(bedA)).cleanliness, 'clean');
      final assign = (await env.auditFor('housekeeping.assign')).single;
      final clean = await env.auditFor('bed.mark_clean');
      expect(clean, hasLength(2));
      expect({
        assign.operationId,
        for (final c in clean) c.operationId,
      }, hasLength(1));
    },
  );

  group('reassign (housekeeping.reassign)', () {
    test('changes the housekeeper on the open task; the audit keeps old '
        'and new', () async {
      await repo.assign(desk, bedA, rose);
      await repo.reassign(desk, bedA, jane);
      final task = (await tasks()).single;
      expect(task.housekeeperId, jane);
      expect(task.completedAt, isNull);
      final audit = (await env.auditFor('housekeeping.reassign')).single;
      expect((jsonDecode(audit.beforeJson!) as Map)['housekeeper_id'], rose);
      expect((jsonDecode(audit.afterJson) as Map)['housekeeper_id'], jane);
    });

    test('refused without an open task, or to the same housekeeper', () async {
      await expectLater(
        repo.reassign(desk, bedA, jane),
        throwsA(isA<HousekeepingRefused>()),
      );
      await repo.assign(desk, bedA, rose);
      await expectLater(
        repo.reassign(desk, bedA, rose),
        throwsA(isA<HousekeepingRefused>()),
      );
    });
  });

  group('closing a bed or room cancels its cleaning (housekeeping.cancel)', () {
    test('the task is cancelled with time and user; the bed stays not '
        'cleaned; reopened, it needs assigning again', () async {
      await repo.assign(desk, bedA, rose);
      await rooms.deactivateBed(supervisor, bedA);
      final task = (await tasks()).single;
      expect(
        (task.cancelledAt, task.cancelledBy),
        (env.clock.now(), supervisor.id),
      );
      expect(task.completedAt, isNull);
      expect((await bed(bedA)).cleanliness, 'not_cleaned');
      expect(
        (await env.auditFor('housekeeping.cancel')).single.entity,
        'housekeeping_tasks',
      );

      await rooms.reactivateBed(supervisor, bedA);
      final reopened = await repo.watchBed(bedA).first;
      expect(reopened.openTask, isNull);
      expect(
        cleaningLine(reopened.openTask?.housekeeperName),
        'Needs cleaning · assign',
      );
      // A cancelled task never makes the bed clean.
      await expectLater(
        repo.markClean(desk, bedA),
        throwsA(isA<HousekeepingRefused>()),
      );
      // It can be given out again.
      await repo.assign(desk, bedA, jane);
      expect(
        (await repo.watchBed(bedA).first).openTask!.housekeeperName,
        'Jane',
      );
    });

    test('closing the room cancels every bed’s open task', () async {
      await repo.assign(desk, bedA, rose);
      await rooms.deactivateRoom(supervisor, r7.id);
      expect((await tasks()).single.cancelledAt, isNotNull);
    });
  });

  group('deactivating a housekeeper (FD-9 guard on AD-4)', () {
    test('refused while they have a bed to clean; allowed once it’s done or '
        'reassigned', () async {
      await repo.assign(desk, bedA, rose);
      await expectLater(
        staff.deactivateHousekeeper(supervisor, rose),
        throwsA(
          isA<StaffRuleViolation>().having(
            (e) => e.message,
            'message',
            'Rose has a bed to clean. Finish or reassign it first.',
          ),
        ),
      );
      await repo.reassign(desk, bedA, jane);
      await staff.deactivateHousekeeper(supervisor, rose);
      await repo.markClean(desk, bedA);
      await staff.deactivateHousekeeper(supervisor, jane);
    });
  });

  test(
    'names: full names in the dropdown when two share a first name',
    () async {
      await staff.addHousekeeper(supervisor, name: 'Rose Mutua', phone: '');
      final names = await repo.names();
      expect(names[rose], 'Rose Akinyi');
      expect(names[jane], 'Jane');
      expect(housekeeperNames(await repo.watchHousekeepers().first).length, 3);
    },
  );
}
