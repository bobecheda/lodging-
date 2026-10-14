import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/audit/audit_writer.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:uuid/uuid.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 14, 19);
  late FixedClock clock;
  late AppDatabase db;
  late AuditWriter audit;
  late String deviceId;
  late String adminId;

  /// Rows written before this are setup; audit_log is append-only, so tests
  /// look only at what came after instead of deleting.
  late DateTime since;

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
    clock.advance(const Duration(minutes: 5));
    since = clock.now();
  });

  tearDown(() => db.close());

  Future<RoomRow> createRoom(String number) => audit.writeWithAudit(
    action: 'room.create',
    userId: adminId,
    body: (w) => w.insert(db.rooms, RoomsCompanion.insert(roomNumber: number)),
  );

  Future<List<OutboxRow>> outbox() =>
      (db.select(db.outbox)
            ..where((o) => o.createdAt.isBiggerOrEqualValue(since))
            ..orderBy([(o) => OrderingTerm.asc(o.seq)]))
          .get();

  Future<List<AuditLogRow>> auditRows() => (db.select(
    db.auditLog,
  )..where((a) => a.at.isBiggerOrEqualValue(since))).get();

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
  });

  // Column-map stamping, verified against the drift version in pubspec.lock.
  group('stamped columns', () {
    test(
      '1. a .insert(...) row with no stamped fields saves through the writer '
      'with created_at from the clock',
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
        expect(room.updatedAt, clock.now());
        expect(room.deviceId, deviceId);
      },
    );

    test(
      '2. a direct insert without the writer throws the StateError',
      () async {
        await expectLater(
          () =>
              db.into(db.rooms).insert(RoomsCompanion.insert(roomNumber: '3')),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'must be stamped by writeWithAudit',
            ),
          ),
        );
        expect(await count(db.rooms), 0);
      },
    );

    test(
      '3. an id passed by the caller is kept; an omitted id gets a UUID',
      () async {
        final kept = await audit.writeWithAudit(
          action: 'room.create',
          userId: adminId,
          body: (w) => w.insert(
            db.rooms,
            RoomsCompanion.insert(
              id: const Value('room-fixed'),
              roomNumber: '4',
            ),
          ),
        );
        expect(kept.id, 'room-fixed');

        final generated = await createRoom('5');
        expect(Uuid.isValidUUID(fromString: generated.id), isTrue);
        expect(generated.id, isNot(kept.id));
        expect(
          [for (final e in await auditRows()) e.entityId],
          ['room-fixed', generated.id],
        );
      },
    );

    test('4. DateTimes round-trip in UTC through Variable<DateTime>', () async {
      clock.set(DateTime.utc(2026, 10, 14, 21, 30, 15, 123));
      final room = await createRoom('3');
      expect(room.createdAt.isUtc, isTrue);
      expect(room.createdAt, DateTime.utc(2026, 10, 14, 21, 30, 15, 123));

      final reread = await (db.select(
        db.rooms,
      )..where((r) => r.id.equals(room.id))).getSingle();
      expect(reread.createdAt.isUtc, isTrue);
      expect(reread.createdAt, room.createdAt);

      final raw = await db
          .customSelect(
            'SELECT created_at FROM rooms WHERE id = ?',
            variables: [Variable(room.id)],
          )
          .getSingle();
      expect(raw.read<String>('created_at'), '2026-10-14T21:30:15.123Z');

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
      expect(updated.updatedAt.isUtc, isTrue);
      expect(updated.updatedAt, DateTime.utc(2026, 10, 14, 22, 30, 15, 123));
      expect(updated.createdAt, room.createdAt);
    });
  });

  group('update', () {
    test('records before and after, bumps updated_at only', () async {
      final room = await createRoom('3');
      clock.advance(const Duration(hours: 1));
      since = clock.now();

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
      // Only the columns that changed.
      expect(before.keys, unorderedEquals(['floor', 'updated_at']));
      expect(after.keys, unorderedEquals(['floor', 'updated_at']));
      expect(before['floor'], isNull);
      expect(after['floor'], '1st');
      expect(after['updated_at'], '2026-10-14T20:05:00.000Z');
      // The outbox still gets the full row.
      expect(
        jsonDecode((await outbox()).first.payloadJson)['room_number'],
        '3',
      );
      expect((await outbox()).map((o) => o.targetTable), [
        'rooms',
        'audit_log',
      ]);
    });

    test('stamps device_id and never writes created_at', () async {
      final updated = await audit.writeWithAudit(
        action: 'price.update',
        userId: adminId,
        body: (w) => w.update(
          db.bedCategories,
          SeedIds.deluxe,
          const BedCategoriesCompanion(pricePerBlock: Value(800)),
        ),
      );
      expect(updated.pricePerBlock, 800);
      expect(updated.deviceId, deviceId); // was 'seed'
      expect(updated.createdAt, t0);
      expect(updated.updatedAt, clock.now());
      final entry = (await auditRows()).single;
      expect(jsonDecode(entry.beforeJson!)['device_id'], seedDeviceId);
      expect(jsonDecode(entry.afterJson)['price_per_block'], 800);
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

    test(
      'rows of one call share an operation_id; another call gets a new one',
      () async {
        await audit.writeWithAudit(
          action: 'room.create',
          userId: adminId,
          body: (w) async {
            await w.insert(db.rooms, RoomsCompanion.insert(roomNumber: '9'));
            await w.insert(db.rooms, RoomsCompanion.insert(roomNumber: '10'));
          },
        );
        await createRoom('11');

        final entries = await auditRows();
        expect(entries, hasLength(3));
        final firstCall = entries[0].operationId;
        expect(firstCall, hasLength(36));
        expect(entries[1].operationId, firstCall);
        expect(entries[2].operationId, isNot(firstCall));
        expect(
          jsonDecode((await outbox())[1].payloadJson)['operation_id'],
          firstCall,
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

  group('redaction', () {
    test(
      'password_hash is redacted in audit JSON but synced in the outbox',
      () async {
        final user = await audit.writeWithAudit(
          action: 'user.create',
          userId: adminId,
          body: (w) => w.insert(
            db.users,
            UsersCompanion.insert(
              fullName: 'Desk',
              username: 'desk',
              passwordHash: r'$2b$10$secret',
              role: 'receptionist',
              mustChangePassword: true,
            ),
          ),
        );
        final entry = (await auditRows()).single;
        expect(jsonDecode(entry.afterJson)['password_hash'], '[redacted]');
        expect(jsonDecode(entry.afterJson)['username'], 'desk');
        final queued = (await outbox()).first;
        expect(queued.targetRowId, user.id);
        expect(
          jsonDecode(queued.payloadJson)['password_hash'],
          r'$2b$10$secret',
        );
        expect(
          jsonDecode((await outbox()).last.payloadJson)['after_json'],
          isNot(contains('secret')),
        );
      },
    );

    test('guest personal data is redacted in audit JSON', () async {
      await audit.writeWithAudit(
        action: 'guest.create',
        userId: adminId,
        body: (w) => w.insert(
          db.guests,
          GuestsCompanion.insert(
            fullName: 'John Guest',
            phone: '0712345678',
            idType: const Value('national_id'),
            idNumber: const Value('12345678'),
          ),
        ),
      );
      final after = jsonDecode((await auditRows()).single.afterJson) as Map;
      expect(after['full_name'], '[redacted]');
      expect(after['phone'], '[redacted]');
      expect(after['id_number'], '[redacted]');
      expect(after['id_type'], 'national_id');
      final payload = jsonDecode((await outbox()).first.payloadJson) as Map;
      expect(payload['id_number'], '12345678');
    });
  });

  group('per-write action', () {
    test(
      'one call can record several actions under one operation_id',
      () async {
        await audit.writeWithAudit(
          action: 'user.create',
          userId: adminId,
          body: (w) async {
            await w.insert(
              db.users,
              UsersCompanion.insert(
                fullName: 'Second',
                username: 'second',
                passwordHash: 'hash',
                role: 'admin',
                mustChangePassword: false,
              ),
            );
            await w.update(
              db.settings,
              'lodging_name',
              const SettingsCompanion(value: Value('Sunrise Lodge')),
              action: 'settings.update',
            );
          },
        );
        final entries = await auditRows();
        expect(
          [for (final e in entries) (e.action, e.entity)],
          [('user.create', 'users'), ('settings.update', 'settings')],
        );
        expect(entries.map((e) => e.operationId).toSet(), hasLength(1));
      },
    );

    test('an override must be entity.verb too', () async {
      await expectLater(
        audit.writeWithAudit(
          action: 'room.create',
          userId: adminId,
          body: (w) => w.insert(
            db.rooms,
            RoomsCompanion.insert(roomNumber: '20'),
            action: 'Create',
          ),
        ),
        throwsArgumentError,
      );
      expect(await count(db.rooms), 0);
    });
  });

  group('write order and lifetime', () {
    test('a nested writeWithAudit queues rows in actual write order', () async {
      await audit.writeWithAudit(
        action: 'room.create',
        userId: adminId,
        body: (w) async {
          final room = await w.insert(
            db.rooms,
            RoomsCompanion.insert(roomNumber: '12'),
          );
          await audit.writeWithAudit(
            action: 'bed.create',
            userId: adminId,
            body: (inner) => inner.insert(
              db.beds,
              BedsCompanion.insert(
                roomId: room.id,
                label: 'A',
                categoryId: SeedIds.vip,
                cleanliness: 'clean',
              ),
            ),
          );
        },
      );
      expect(
        [for (final o in await outbox()) o.targetTable],
        ['rooms', 'audit_log', 'beds', 'audit_log'],
      );
    });

    test('a write the body did not await is still saved and audited', () async {
      await audit.writeWithAudit(
        action: 'room.create',
        userId: adminId,
        body: (w) async {
          unawaited(
            w.insert(db.rooms, RoomsCompanion.insert(roomNumber: '13')),
          );
        },
      );
      expect(await count(db.rooms), 1);
      expect((await auditRows()).map((e) => e.entity), ['rooms']);
    });

    test('a failed write the body did not await saves nothing', () async {
      await expectLater(
        audit.writeWithAudit(
          action: 'room.create',
          userId: adminId,
          body: (w) async {
            final room = await w.insert(
              db.rooms,
              RoomsCompanion.insert(roomNumber: '14'),
            );
            unawaited(
              w.insert(
                db.beds,
                BedsCompanion.insert(
                  roomId: room.id,
                  label: 'C', // violates the label CHECK
                  categoryId: SeedIds.vip,
                  cleanliness: 'clean',
                ),
              ),
            );
          },
        ),
        throwsA(anything),
      );
      expect(await count(db.rooms), 0);
      expect(await auditRows(), isEmpty);
    });

    test('using the writes after the call returns throws', () async {
      late AuditedWrites escaped;
      await audit.writeWithAudit(
        action: 'room.create',
        userId: adminId,
        body: (w) {
          escaped = w;
          return w.insert(db.rooms, RoomsCompanion.insert(roomNumber: '15'));
        },
      );
      expect(
        () => escaped.insert(db.rooms, RoomsCompanion.insert(roomNumber: '16')),
        throwsStateError,
      );
      expect(await count(db.rooms), 1);
    });

    test('two updates of one row in one call both apply', () async {
      final room = await createRoom('17');
      clock.advance(const Duration(minutes: 1));
      final updated = await audit.writeWithAudit(
        action: 'room.update',
        userId: adminId,
        body: (w) async {
          await w.update(
            db.rooms,
            room.id,
            const RoomsCompanion(floor: Value('1st')),
          );
          return w.update(
            db.rooms,
            room.id,
            const RoomsCompanion(notes: Value('quiet')),
          );
        },
      );
      expect(updated.floor, '1st');
      expect(updated.notes, 'quiet');
      expect(
        updated.updatedAt,
        clock.now().add(const Duration(milliseconds: 1)),
      );
    });
  });

  group('database guards', () {
    test('a direct update that does not move updated_at is rejected', () async {
      final room = await createRoom('18');
      await expectLater(
        (db.update(db.rooms)..where((r) => r.id.equals(room.id))).write(
          const RoomsCompanion(floor: Value('2nd')),
        ),
        throwsA(
          predicate((e) => '$e'.contains('must be stamped by writeWithAudit')),
        ),
      );
    });

    test('audit_log rows cannot be updated or deleted', () async {
      await createRoom('19');
      final entry = (await auditRows()).single;
      await expectLater(
        (db.update(db.auditLog)..where((a) => a.id.equals(entry.id))).write(
          const AuditLogCompanion(action: Value('room.delete')),
        ),
        throwsA(predicate((e) => '$e'.contains('audit_log is append-only'))),
      );
      await expectLater(
        db.delete(db.auditLog).go(),
        throwsA(predicate((e) => '$e'.contains('audit_log is append-only'))),
      );
    });

    test('stays, payments, charges and voids cannot be deleted', () async {
      final triggers = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' "
            "AND name LIKE '%_no_delete'",
          )
          .map((r) => r.read<String>('name'))
          .get();
      expect(
        triggers,
        unorderedEquals([
          'stays_no_delete',
          'payments_no_delete',
          'stay_charges_no_delete',
          'voids_no_delete',
          'audit_log_no_delete',
        ]),
      );
      await audit.writeWithAudit(
        action: 'void.create',
        userId: adminId,
        body: (w) => w.insert(
          db.voids,
          VoidsCompanion.insert(
            targetType: 'payment',
            targetId: w.newId(),
            reason: 'Wrong amount',
            voidedBy: adminId,
            voidedAt: w.now,
          ),
        ),
      );
      await expectLater(
        db.delete(db.voids).go(),
        throwsA(
          predicate((e) => '$e'.contains('voids rows are never deleted')),
        ),
      );
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
      expect(entry.operationId, hasLength(36));
      expect(entry.beforeJson, isNull);
      expect(jsonDecode(entry.afterJson), {'username': 'owner'});
      expect(
        [for (final o in await outbox()) (o.targetTable, o.targetRowId)],
        [('audit_log', entry.id)],
      );
    });
  });
}
