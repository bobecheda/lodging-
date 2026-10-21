import 'dart:convert';

import 'package:drift/drift.dart' show CustomExpression, OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late RoomsRepository rooms;
  late UserAccount supervisor;

  setUp(() async {
    env = TestEnv();
    rooms = RoomsRepository(env.db, env.audit);
    supervisor = await env.createFirstSupervisor(testSetup);
  });
  tearDown(() => env.close());

  Future<RoomSummary> twoBedRoom([String number = '5']) => rooms.createRoom(
    supervisor,
    NewRoom(
      number: number,
      floor: 'Ground',
      notes: null,
      bedACategoryId: SeedIds.normal,
      bedBCategoryId: SeedIds.deluxe,
    ),
  );

  BedSummary bedOf(RoomSummary room, BedLabel label) =>
      room.beds.firstWhere((b) => b.label == label);

  Matcher blockedBecause(String message) => throwsA(
    isA<RoomRuleViolation>().having((e) => e.message, 'message', message),
  );

  group('create', () {
    test(
      'a 2-bed room: normalized number, clean beds with categories',
      () async {
        final room = await rooms.createRoom(
          supervisor,
          const NewRoom(
            number: ' 3a ',
            floor: ' First ',
            notes: '  ',
            bedACategoryId: SeedIds.vip,
            bedBCategoryId: SeedIds.comfort,
          ),
        );
        expect(room.number, '3A');
        expect(room.floor, 'First');
        expect(room.notes, isNull);
        expect(room.isActive, isTrue);
        expect(
          [
            for (final b in room.beds)
              (b.label, b.categoryName, b.pricePerNight, b.cleanliness),
          ],
          [
            (BedLabel.a, 'VIP', 1000, Cleanliness.clean),
            (BedLabel.b, 'Comfort', 600, Cleanliness.clean),
          ],
        );
      },
    );

    test('audits room.create and bed.create as one operation', () async {
      await twoBedRoom();
      final entries =
          await (env.db.select(env.db.auditLog)
                ..where((a) => a.action.isIn(['room.create', 'bed.create']))
                ..orderBy([
                  (a) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
                ]))
              .get();
      expect(entries.map((e) => e.action), [
        'room.create',
        'bed.create',
        'bed.create',
      ]);
      expect(entries.map((e) => e.operationId).toSet(), hasLength(1));
      expect(entries.map((e) => e.userId).toSet(), {supervisor.id});
    });

    test('a 1-bed room has bed A only', () async {
      final room = await rooms.createRoom(
        supervisor,
        const NewRoom(
          number: '1',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.vip,
          bedBCategoryId: null,
        ),
      );
      expect(room.beds.map((b) => b.label), [BedLabel.a]);
    });

    test('room numbers are unique ignoring case and spaces', () async {
      await twoBedRoom('3A');
      await expectLater(twoBedRoom(' 3a'), throwsA(isA<RoomNumberTaken>()));
      expect(await rooms.rooms(), hasLength(1));
    });

    test('the database itself refuses a non-normalized number', () async {
      await expectLater(
        env.audit.writeWithAudit(
          action: 'room.create',
          userId: supervisor.id,
          body: (w) =>
              w.insert(env.db.rooms, RoomsCompanion.insert(roomNumber: '3a')),
        ),
        throwsA(predicate((e) => '$e'.contains('CHECK constraint failed'))),
      );
    });

    test('rejects an invalid form without writing', () async {
      await expectLater(
        rooms.createRoom(
          supervisor,
          const NewRoom(
            number: 'Room 5',
            floor: null,
            notes: null,
            bedACategoryId: 'no-such-category',
            bedBCategoryId: null,
          ),
        ),
        throwsA(
          isA<InvalidRoom>().having((e) => e.errors.keys, 'fields', {
            RoomField.number,
            RoomField.bedA,
          }),
        ),
      );
      expect(await rooms.rooms(), isEmpty);
    });
  });

  group('supervisor only (AD-1)', () {
    test(
      'a receptionist cannot change rooms or beds, and nothing is written',
      () async {
        final room = await twoBedRoom();
        final desk = await env.addReceptionist('desk');
        final auditBefore = await env.db.select(env.db.auditLog).get();

        for (final attempt in <Future<Object?> Function()>[
          () => twoBedRoom('6').then(
            (_) => rooms.createRoom(
              desk,
              const NewRoom(
                number: '7',
                floor: null,
                notes: null,
                bedACategoryId: SeedIds.vip,
                bedBCategoryId: null,
              ),
            ),
          ),
          () => rooms.updateRoom(
            desk,
            room.id,
            const RoomEdit(number: '9', floor: null, notes: null),
          ),
          () => rooms.deactivateRoom(desk, room.id),
          () => rooms.deactivateBed(desk, bedOf(room, BedLabel.b).id),
        ]) {
          await expectLater(attempt(), throwsA(isA<NotPermitted>()));
        }
        // Only the owner's own room 6 (created inside the first attempt) was added.
        final auditAfter = await env.db.select(env.db.auditLog).get();
        expect(
          auditAfter.skip(auditBefore.length).map((e) => e.userId).toSet(),
          {supervisor.id},
        );
      },
    );
  });

  group('edit room', () {
    test('saves number, floor and a bed category as one operation', () async {
      final room = await twoBedRoom();
      final updated = await rooms.updateRoom(
        supervisor,
        room.id,
        const RoomEdit(
          number: '5b',
          floor: 'First',
          notes: 'Near the stairs',
          bedCategories: {BedLabel.b: SeedIds.vip},
        ),
      );
      expect(updated.number, '5B');
      expect(updated.floor, 'First');
      expect(bedOf(updated, BedLabel.b).categoryName, 'VIP');
      expect(bedOf(updated, BedLabel.a).categoryName, 'Normal');

      final entries =
          await (env.db.select(env.db.auditLog)
                ..where((a) => a.action.isIn(['room.update', 'bed.update']))
                ..orderBy([
                  (a) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
                ]))
              .get();
      expect(entries.map((e) => e.action), ['room.update', 'bed.update']);
      expect(entries.map((e) => e.operationId).toSet(), hasLength(1));
      // Old and new category in the audit trail.
      expect(
        jsonDecode(entries.last.beforeJson!)['category_id'],
        SeedIds.deluxe,
      );
      expect(jsonDecode(entries.last.afterJson)['category_id'], SeedIds.vip);
    });

    test('nothing changed: no write, no audit', () async {
      final room = await twoBedRoom();
      await rooms.updateRoom(
        supervisor,
        room.id,
        const RoomEdit(
          number: '5',
          floor: 'Ground',
          notes: null,
          bedCategories: {BedLabel.a: SeedIds.normal},
        ),
      );
      expect(await env.auditFor('room.update'), isEmpty);
    });

    test('a new number must be free', () async {
      await twoBedRoom('4');
      final room = await twoBedRoom('5');
      await expectLater(
        rooms.updateRoom(
          supervisor,
          room.id,
          const RoomEdit(number: '4', floor: null, notes: null),
        ),
        throwsA(isA<RoomNumberTaken>()),
      );
    });

    test('changing a category affects new check-ins only', () async {
      final room = await twoBedRoom();
      final bedA = bedOf(room, BedLabel.a); // Normal, 500
      final stayId = await env.checkIn(bedA.id, by: supervisor);

      await rooms.updateRoom(
        supervisor,
        room.id,
        const RoomEdit(
          number: '5',
          floor: 'Ground',
          notes: null,
          bedCategories: {BedLabel.a: SeedIds.vip},
        ),
      );
      final charge = await (env.db.select(
        env.db.stayCharges,
      )..where((c) => c.stayId.equals(stayId))).getSingle();
      expect(charge.pricePerNight, 500);
      expect(bedOf(await rooms.room(room.id), BedLabel.a).pricePerNight, 1000);
    });
  });

  group(
    'deactivate (guards tested with a stay inserted through the writer)',
    () {
      test('a bed with a guest cannot be deactivated', () async {
        final room = await twoBedRoom();
        final bedB = bedOf(room, BedLabel.b);
        await env.checkIn(bedB.id, by: supervisor);

        await expectLater(
          rooms.deactivateBed(supervisor, bedB.id),
          blockedBecause('Bed B has a guest right now. Check them out first.'),
        );
        expect(bedOf(await rooms.room(room.id), BedLabel.b).isActive, isTrue);
        expect(await env.auditFor('bed.deactivate'), isEmpty);
      });

      test('a room with a guest in any bed cannot be deactivated', () async {
        final room = await twoBedRoom();
        await env.checkIn(bedOf(room, BedLabel.b).id, by: supervisor);

        await expectLater(
          rooms.deactivateRoom(supervisor, room.id),
          blockedBecause('Bed B has a guest right now. Check them out first.'),
        );
        expect((await rooms.room(room.id)).isActive, isTrue);
        expect(await env.auditFor('room.deactivate'), isEmpty);
      });

      test('after checkout, the bed and the room can be deactivated', () async {
        final room = await twoBedRoom();
        final bedB = bedOf(room, BedLabel.b);
        final stayId = await env.checkIn(bedB.id, by: supervisor);
        await env.checkOut(stayId, by: supervisor);

        final afterBed = await rooms.deactivateBed(supervisor, bedB.id);
        expect(bedOf(afterBed, BedLabel.b).isActive, isFalse);
        final afterRoom = await rooms.deactivateRoom(supervisor, room.id);
        expect(afterRoom.isActive, isFalse);
        expect(await env.auditFor('bed.deactivate'), hasLength(1));
        expect(await env.auditFor('room.deactivate'), hasLength(1));
      });

      test(
        "an open room's last active bed: deactivate the room instead",
        () async {
          final room = await twoBedRoom();
          await rooms.deactivateBed(supervisor, bedOf(room, BedLabel.b).id);
          await expectLater(
            rooms.deactivateBed(supervisor, bedOf(room, BedLabel.a).id),
            blockedBecause('Deactivate the room instead.'),
          );
        },
      );

      test('nothing is ever deleted', () async {
        final room = await twoBedRoom();
        await rooms.deactivateBed(supervisor, bedOf(room, BedLabel.b).id);
        await rooms.deactivateRoom(supervisor, room.id);
        expect(await env.db.select(env.db.rooms).get(), hasLength(1));
        expect(await env.db.select(env.db.beds).get(), hasLength(2));
      });
    },
  );

  group('reactivate', () {
    test('a reopened bed comes back not_cleaned (bed.reactivate)', () async {
      final room = await twoBedRoom();
      final bedB = bedOf(room, BedLabel.b);
      await rooms.deactivateBed(supervisor, bedB.id);
      final after = await rooms.reactivateBed(supervisor, bedB.id);
      expect(bedOf(after, BedLabel.b).isActive, isTrue);
      expect(bedOf(after, BedLabel.b).cleanliness, Cleanliness.notCleaned);
      expect(await env.auditFor('bed.reactivate'), hasLength(1));
    });

    test(
      "a reopened room's beds come back not_cleaned, one operation",
      () async {
        final room = await twoBedRoom();
        await rooms.deactivateRoom(supervisor, room.id);
        final after = await rooms.reactivateRoom(supervisor, room.id);
        expect(after.isActive, isTrue);
        expect(after.beds.map((b) => b.cleanliness).toSet(), {
          Cleanliness.notCleaned,
        });
        final entries = await env.auditFor('room.reactivate');
        expect(entries.map((e) => e.entity), ['rooms', 'beds', 'beds']);
        expect(entries.map((e) => e.operationId).toSet(), hasLength(1));
      },
    );

    test('a room with no active bed cannot reopen', () async {
      final room = await rooms.createRoom(
        supervisor,
        const NewRoom(
          number: '1',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.vip,
          bedBCategoryId: null,
        ),
      );
      await rooms.deactivateRoom(supervisor, room.id);
      await rooms.deactivateBed(supervisor, bedOf(room, BedLabel.a).id);
      await expectLater(
        rooms.reactivateRoom(supervisor, room.id),
        blockedBecause('Reactivate a bed first.'),
      );
    });
  });

  group('add bed B', () {
    test('a 1-bed room gets a clean bed B (bed.create)', () async {
      final room = await rooms.createRoom(
        supervisor,
        const NewRoom(
          number: '1',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.vip,
          bedBCategoryId: null,
        ),
      );
      final after = await rooms.addBed(supervisor, room.id, SeedIds.normal);
      expect(after.beds.map((b) => b.label), [BedLabel.a, BedLabel.b]);
      expect(bedOf(after, BedLabel.b).cleanliness, Cleanliness.clean);
    });

    test('a room never gets a third bed', () async {
      final room = await twoBedRoom();
      await expectLater(
        rooms.addBed(supervisor, room.id, SeedIds.normal),
        blockedBecause('This room already has beds A and B.'),
      );
    });

    test('an inactive category cannot be chosen', () async {
      await env.audit.writeWithAudit(
        action: 'category.update',
        userId: supervisor.id,
        body: (w) => w.update(
          env.db.bedCategories,
          SeedIds.comfort,
          const BedCategoriesCompanion(isActive: Value(false)),
        ),
      );
      final room = await rooms.createRoom(
        supervisor,
        const NewRoom(
          number: '1',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.vip,
          bedBCategoryId: null,
        ),
      );
      await expectLater(
        rooms.addBed(supervisor, room.id, SeedIds.comfort),
        throwsA(isA<InvalidRoom>()),
      );
    });
  });

  test('rooms list in natural order', () async {
    for (final n in ['10', '2', '1']) {
      await twoBedRoom(n);
    }
    expect((await rooms.rooms()).map((r) => r.number), ['1', '2', '10']);
  });
}
