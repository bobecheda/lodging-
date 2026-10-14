import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/audit/audit_writer.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 14, 19);
  late FixedClock clock;
  late AppDatabase db;
  late AuditWriter audit;
  late String deviceId;
  late String adminId;

  setUp(() async {
    clock = FixedClock(t0);
    db = AppDatabase(NativeDatabase.memory(), clock: clock);
    audit = AuditWriter(db, clock);
    deviceId = await db.deviceId();
    adminId = (await audit.writeWithAudit(
      action: 'user.create',
      userId: null,
      body: (w) => w.insert(
        db.users,
        UsersCompanion.insert(
          fullName: 'Owner',
          username: 'owner',
          passwordHash: 'hash',
          role: 'admin',
          mustChangePassword: false,
        ),
      ),
    )).id;
    // Start each test from an empty audit trail and outbox.
    await db.delete(db.outbox).go();
    await db.delete(db.auditLog).go();
    clock.advance(const Duration(minutes: 5));
  });

  tearDown(() => db.close());

  Future<RoomRow> createRoom(String number) => audit.writeWithAudit(
    action: 'room.create',
    userId: adminId,
    body: (w) => w.insert(db.rooms, RoomsCompanion.insert(roomNumber: number)),
  );

  Future<List<OutboxRow>> outbox() =>
      (db.select(db.outbox)..orderBy([(o) => OrderingTerm.asc(o.seq)])).get();

  Future<List<AuditLogRow>> auditRows() => db.select(db.auditLog).get();

  Future<int> count(TableInfo table) async =>
      (await db
              .customSelect(
                'SELECT COUNT(*) AS n FROM ${table.actualTableName}',
              )
              .getSingle())
          .read<int>('n');

  group('insert', () {
    test('stamps id, timestamps and device id', () async {
      final room = await createRoom('3');
      expect(room.id, hasLength(36));
      expect(room.createdAt, clock.now());
      expect(room.updatedAt, clock.now());
      expect(room.deviceId, deviceId);
    });

    test('writes one audit row with no before and the row as after', () async {
      final room = await createRoom('3');
      final entry = (await auditRows()).single;
      expect(entry.action, 'room.create');
      expect(entry.userId, adminId);
      expect(entry.at, clock.now());
      expect(entry.deviceId, deviceId);
      expect(entry.entity, 'rooms');
      expect(entry.entityId, room.id);
      expect(entry.beforeJson, isNull);
      expect(jsonDecode(entry.afterJson), {
        'id': room.id,
        'created_at': '2026-10-14T19:05:00.000Z',
        'updated_at': '2026-10-14T19:05:00.000Z',
        'device_id': deviceId,
        'room_number': '3',
        'floor': null,
        'notes': null,
        'is_active': true,
      });
    });

    test('queues the business row, then its audit row', () async {
      final room = await createRoom('3');
      final entry = (await auditRows()).single;
      final queued = await outbox();
      expect(
        [for (final o in queued) (o.targetTable, o.targetRowId)],
        [('rooms', room.id), ('audit_log', entry.id)],
      );
      expect(jsonDecode(queued[0].payloadJson), jsonDecode(entry.afterJson));
      expect(jsonDecode(queued[1].payloadJson)['action'], 'room.create');
      for (final o in queued) {
        expect(o.createdAt, clock.now());
        expect(o.attempts, 0);
        expect(o.sentAt, isNull);
      }
    });

    test('keeps an id supplied by the caller', () async {
      final room = await audit.writeWithAudit(
        action: 'room.create',
        userId: adminId,
        body: (w) => w.insert(
          db.rooms,
          RoomsCompanion.insert(id: const Value('room-fixed'), roomNumber: '4'),
        ),
      );
      expect(room.id, 'room-fixed');
    });
  });

  group('stamped columns', () {
    test('a direct insert that bypasses the writer throws', () async {
      await expectLater(
        () => db.into(db.rooms).insert(RoomsCompanion.insert(roomNumber: '3')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'stamped by writeWithAudit',
          ),
        ),
      );
      expect(await count(db.rooms), 0);
    });

    test(
      'the same row through writeWithAudit gets created_at from the clock',
      () async {
        final room = await audit.writeWithAudit(
          action: 'room.create',
          userId: adminId,
          body: (w) =>
              w.insert(db.rooms, RoomsCompanion.insert(roomNumber: '3')),
        );
        expect(room.roomNumber, '3');
        expect(room.createdAt, DateTime.utc(2026, 10, 14, 19, 5));
        expect(room.createdAt, clock.now());
      },
    );
  });

  group('update', () {
    test('records before and after, bumps updated_at only', () async {
      final room = await createRoom('3');
      await db.delete(db.auditLog).go();
      await db.delete(db.outbox).go();
      clock.advance(const Duration(hours: 1));

      final updated = await audit.writeWithAudit(
        action: 'room.update',
        userId: adminId,
        body: (w) => w.update(
          db.rooms,
          room.id,
          const RoomsCompanion(floor: Value('1st')),
        ),
      );

      expect(updated.floor, '1st');
      expect(updated.createdAt, room.createdAt);
      expect(updated.updatedAt, clock.now());

      final entry = (await auditRows()).single;
      final before = jsonDecode(entry.beforeJson!) as Map;
      final after = jsonDecode(entry.afterJson) as Map;
      expect(before['floor'], isNull);
      expect(after['floor'], '1st');
      expect(after['updated_at'], '2026-10-14T20:05:00.000Z');
      expect((await outbox()).map((o) => o.targetTable), [
        'rooms',
        'audit_log',
      ]);
    });

    test('works on settings, keyed by key', () async {
      await audit.writeWithAudit(
        action: 'settings.update',
        userId: adminId,
        body: (w) => w.update(
          db.settings,
          'lodging_name',
          SettingsCompanion(
            value: const Value('Sunrise Lodge'),
            updatedBy: Value(adminId),
          ),
        ),
      );
      final row = await (db.select(
        db.settings,
      )..where((s) => s.key.equals('lodging_name'))).getSingle();
      expect(row.value, 'Sunrise Lodge');
      expect(row.updatedAt, clock.now());
      expect((await auditRows()).single.entityId, 'lodging_name');
    });

    test('throws for a missing row and saves nothing', () async {
      await expectLater(
        audit.writeWithAudit(
          action: 'room.update',
          userId: adminId,
          body: (w) => w.update(
            db.rooms,
            'missing',
            const RoomsCompanion(floor: Value('1st')),
          ),
        ),
        throwsStateError,
      );
      expect(await auditRows(), isEmpty);
      expect(await outbox(), isEmpty);
    });

    test('cannot change the primary key, created_at or device_id', () async {
      final room = await createRoom('3');
      for (final changes in [
        const RoomsCompanion(id: Value('other')),
        RoomsCompanion(createdAt: Value(t0)),
        const RoomsCompanion(deviceId: Value('other')),
      ]) {
        await expectLater(
          audit.writeWithAudit(
            action: 'room.update',
            userId: adminId,
            body: (w) => w.update(db.rooms, room.id, changes),
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('one transaction', () {
    test(
      'every changed row gets its own audit row, outbox in write order',
      () async {
        final ids = await audit.writeWithAudit(
          action: 'room.create',
          userId: adminId,
          body: (w) async {
            final room = await w.insert(
              db.rooms,
              RoomsCompanion.insert(roomNumber: '5'),
            );
            final bedA = await w.insert(
              db.beds,
              BedsCompanion.insert(
                roomId: room.id,
                label: 'A',
                categoryId: SeedIds.vip,
                cleanliness: 'clean',
              ),
            );
            return [room.id, bedA.id];
          },
        );

        final entries = await auditRows();
        expect(
          [for (final e in entries) (e.entity, e.entityId)],
          [('rooms', ids[0]), ('beds', ids[1])],
        );
        expect(entries.map((e) => e.action).toSet(), {'room.create'});
        expect(
          [for (final o in await outbox()) o.targetTable],
          ['rooms', 'audit_log', 'beds', 'audit_log'],
        );
      },
    );

    test('a failure part-way saves nothing', () async {
      await expectLater(
        audit.writeWithAudit(
          action: 'room.create',
          userId: adminId,
          body: (w) async {
            final room = await w.insert(
              db.rooms,
              RoomsCompanion.insert(roomNumber: '6'),
            );
            // Bed label C violates a CHECK constraint.
            await w.insert(
              db.beds,
              BedsCompanion.insert(
                roomId: room.id,
                label: 'C',
                categoryId: SeedIds.vip,
                cleanliness: 'clean',
              ),
            );
          },
        ),
        throwsA(anything),
      );
      expect(await count(db.rooms), 0);
      expect(await count(db.beds), 0);
      expect(await auditRows(), isEmpty);
      expect(await outbox(), isEmpty);
    });

    test('an exception from the caller saves nothing', () async {
      await expectLater(
        audit.writeWithAudit(
          action: 'room.create',
          userId: adminId,
          body: (w) async {
            await w.insert(db.rooms, RoomsCompanion.insert(roomNumber: '7'));
            throw Exception('cancelled');
          },
        ),
        throwsException,
      );
      expect(await count(db.rooms), 0);
      expect(await auditRows(), isEmpty);
      expect(await outbox(), isEmpty);
    });

    test(
      'receipt_counter changes are saved but not audited or queued',
      () async {
        await audit.writeWithAudit(
          action: 'payment.create',
          userId: adminId,
          body: (w) async {
            await w.update(
              db.receiptCounter,
              deviceId,
              const ReceiptCounterCompanion(nextNumber: Value(2)),
            );
            await w.insert(db.rooms, RoomsCompanion.insert(roomNumber: '8'));
          },
        );
        expect((await db.select(db.receiptCounter).getSingle()).nextNumber, 2);
        expect((await auditRows()).map((e) => e.entity), ['rooms']);
        expect(
          (await outbox()).map((o) => o.targetTable),
          isNot(contains('receipt_counter')),
        );
      },
    );
  });

  group('guards', () {
    test('rejects actions not named entity.verb', () async {
      for (final action in ['create', 'Room.Create', 'room.create.now', '']) {
        expect(
          () => audit.writeWithAudit(
            action: action,
            userId: adminId,
            body: (w) async {},
          ),
          throwsArgumentError,
          reason: action,
        );
      }
    });

    test('rejects a write that changes no synced rows', () async {
      await expectLater(
        audit.writeWithAudit(
          action: 'room.create',
          userId: adminId,
          body: (w) async {},
        ),
        throwsStateError,
      );
    });

    test('refuses system tables', () async {
      for (final write in <Future<Object> Function(AuditedWrites)>[
        (w) => w.insert(
          db.device,
          DeviceCompanion.insert(deviceId: 'x', createdAt: t0),
        ),
        (w) => w.insert(
          db.outbox,
          OutboxCompanion.insert(
            targetTable: 'rooms',
            targetRowId: 'x',
            payloadJson: '{}',
            createdAt: t0,
          ),
        ),
        (w) => w.update(
          db.auditLog,
          'x',
          const AuditLogCompanion(action: Value('x.y')),
        ),
      ]) {
        await expectLater(
          audit.writeWithAudit(
            action: 'room.create',
            userId: adminId,
            body: write,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('recordEvent', () {
    test('writes an audit row and queues it, with no business rows', () async {
      await audit.recordEvent(
        action: 'user.login_failed',
        userId: null,
        entity: 'users',
        entityId: 'owner',
        details: {'username': 'owner'},
      );
      final entry = (await auditRows()).single;
      expect(entry.userId, isNull);
      expect(entry.action, 'user.login_failed');
      expect(entry.beforeJson, isNull);
      expect(jsonDecode(entry.afterJson), {'username': 'owner'});
      expect(
        [for (final o in await outbox()) (o.targetTable, o.targetRowId)],
        [('audit_log', entry.id)],
      );
    });
  });
}
