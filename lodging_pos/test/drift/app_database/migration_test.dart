// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/schema_check.dart';
import 'package:lodging_pos/core/database/test_database_file_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';
import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  /// What the v1 app's `createAll` ran: every table, index and trigger from
  /// the frozen snapshot's SQL, in order.
  List<String> v1AppStatements() {
    final snapshot = jsonDecode(
      File('drift_schemas/app_database/drift_schema_v1.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    return [
      for (final entity in snapshot['fixed_sql']! as List<Object?>)
        for (final sql
            in (entity! as Map<String, Object?>)['sql']! as List<Object?>)
          (sql! as Map<String, Object?>)['sql']! as String,
    ];
  }

  AppDatabase open(QueryExecutor e, {BeforeMigration? beforeMigration}) =>
      AppDatabase(
        e,
        clock: FixedClock(testT0),
        beforeMigration: beforeMigration,
      );

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = open(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // A v1 lodging mid-stay: one guest has both beds of room 7 (one payment),
  // and Bed A was extended (a second payment).
  const t = '2026-10-15T16:00:00.000Z'; // Thu 19:00 Nairobi
  const later = '2026-10-16T08:00:00.000Z';
  const dev = 'device-1';
  const admin = 'user-admin';
  const deluxe = 'cat-deluxe';
  const normal = 'cat-normal';
  const room = 'room-7';
  const bedA = 'bed-7a';
  const bedB = 'bed-7b';
  const guest = 'guest-1';
  const shift = 'shift-1';
  const stayA = 'stay-7a';
  const stayB = 'stay-7b';
  const pay1 = 'pay-1';
  const pay2 = 'pay-2';

  final settings = [
    for (final (key, value) in const [
      ('lodging_name', 'Sunrise Lodge'),
      ('checkout_time', '10:00'),
      ('grace_minutes', '60'),
      ('receipt_prefix', 'R'),
      ('idle_lock_minutes', '10'),
    ])
      (key: key, value: value),
  ];

  test('migration from v1 to v2 keeps every row and gives each charge its '
      'bed’s category', () async {
    final oldUsersData = <v1.UsersData>[
      const v1.UsersData(
        id: admin,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        fullName: 'Grace Owner',
        username: 'owner',
        passwordHash: 'not-a-real-hash',
        role: 'admin',
        isActive: 1,
        mustChangePassword: 0,
      ),
    ];
    final expectedNewUsersData = <v2.UsersData>[
      const v2.UsersData(
        id: admin,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        fullName: 'Grace Owner',
        username: 'owner',
        passwordHash: 'not-a-real-hash',
        role: 'admin',
        isActive: 1,
        mustChangePassword: 0,
      ),
    ];

    // Every key present, so the upgrade adds no settings.
    final oldSettingsData = <v1.SettingsData>[
      for (final s in settings)
        v1.SettingsData(
          key: s.key,
          value: s.value,
          createdAt: t,
          updatedAt: t,
          deviceId: 'seed',
        ),
    ];
    final expectedNewSettingsData = <v2.SettingsData>[
      for (final s in settings)
        v2.SettingsData(
          key: s.key,
          value: s.value,
          createdAt: t,
          updatedAt: t,
          deviceId: 'seed',
        ),
    ];

    final oldBedCategoriesData = <v1.BedCategoriesData>[
      const v1.BedCategoriesData(
        id: deluxe,
        createdAt: t,
        updatedAt: t,
        deviceId: 'seed',
        name: 'Deluxe',
        pricePerNight: 700,
        sortOrder: 1,
        isActive: 1,
      ),
      const v1.BedCategoriesData(
        id: normal,
        createdAt: t,
        updatedAt: t,
        deviceId: 'seed',
        name: 'Normal',
        pricePerNight: 500,
        sortOrder: 2,
        isActive: 1,
      ),
    ];
    final expectedNewBedCategoriesData = <v2.BedCategoriesData>[
      const v2.BedCategoriesData(
        id: deluxe,
        createdAt: t,
        updatedAt: t,
        deviceId: 'seed',
        name: 'Deluxe',
        pricePerNight: 700,
        sortOrder: 1,
        isActive: 1,
      ),
      const v2.BedCategoriesData(
        id: normal,
        createdAt: t,
        updatedAt: t,
        deviceId: 'seed',
        name: 'Normal',
        pricePerNight: 500,
        sortOrder: 2,
        isActive: 1,
      ),
    ];

    final oldRoomsData = <v1.RoomsData>[
      const v1.RoomsData(
        id: room,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        roomNumber: '7',
        floor: '1',
        isActive: 1,
      ),
    ];
    final expectedNewRoomsData = <v2.RoomsData>[
      const v2.RoomsData(
        id: room,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        roomNumber: '7',
        floor: '1',
        isActive: 1,
      ),
    ];

    final oldBedsData = <v1.BedsData>[
      for (final (id, label, category) in const [
        (bedA, 'A', deluxe),
        (bedB, 'B', normal),
      ])
        v1.BedsData(
          id: id,
          createdAt: t,
          updatedAt: t,
          deviceId: dev,
          roomId: room,
          label: label,
          categoryId: category,
          cleanliness: 'clean',
          isActive: 1,
        ),
    ];
    final expectedNewBedsData = <v2.BedsData>[
      for (final (id, label, category) in const [
        (bedA, 'A', deluxe),
        (bedB, 'B', normal),
      ])
        v2.BedsData(
          id: id,
          createdAt: t,
          updatedAt: t,
          deviceId: dev,
          roomId: room,
          label: label,
          categoryId: category,
          cleanliness: 'clean',
          isActive: 1,
        ),
    ];

    final oldGuestsData = <v1.GuestsData>[
      const v1.GuestsData(
        id: guest,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        fullName: 'Grace Achieng',
        phone: '0722418905',
        idType: 'national_id',
        idNumber: '12343921',
      ),
    ];
    final expectedNewGuestsData = <v2.GuestsData>[
      const v2.GuestsData(
        id: guest,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        fullName: 'Grace Achieng',
        phone: '0722418905',
        idType: 'national_id',
        idNumber: '12343921',
      ),
    ];

    final oldShiftsData = <v1.ShiftsData>[
      const v1.ShiftsData(
        id: shift,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        userId: admin,
        openedAt: t,
        openingFloat: 2000,
        status: 'open',
      ),
    ];
    final expectedNewShiftsData = <v2.ShiftsData>[
      const v2.ShiftsData(
        id: shift,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        userId: admin,
        openedAt: t,
        openingFloat: 2000,
        status: 'open',
      ),
    ];

    const paidA = '2026-10-17T07:00:00.000Z'; // Sat 10:00 after the extension
    const paidB = '2026-10-16T07:00:00.000Z'; // Fri 10:00
    final oldStaysData = <v1.StaysData>[
      for (final (id, bed, paid) in const [
        (stayA, bedA, paidA),
        (stayB, bedB, paidB),
      ])
        v1.StaysData(
          id: id,
          createdAt: t,
          updatedAt: t,
          deviceId: dev,
          guestId: guest,
          bedId: bed,
          checkInAt: t,
          paidUntil: paid,
          status: 'active',
          checkedInBy: admin,
        ),
    ];
    final expectedNewStaysData = <v2.StaysData>[
      for (final (id, bed, paid) in const [
        (stayA, bedA, paidA),
        (stayB, bedB, paidB),
      ])
        v2.StaysData(
          id: id,
          createdAt: t,
          updatedAt: t,
          deviceId: dev,
          guestId: guest,
          bedId: bed,
          checkInAt: t,
          paidUntil: paid,
          status: 'active',
          checkedInBy: admin,
        ),
    ];

    final oldPaymentsData = <v1.PaymentsData>[
      const v1.PaymentsData(
        id: pay1,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        receiptNumber: 'R-000001',
        shiftId: shift,
        receivedBy: admin,
        receivedAt: t,
        amount: 1200,
        method: 'cash',
        printCount: 1,
      ),
      const v1.PaymentsData(
        id: pay2,
        createdAt: later,
        updatedAt: later,
        deviceId: dev,
        receiptNumber: 'R-000002',
        shiftId: shift,
        receivedBy: admin,
        receivedAt: later,
        amount: 700,
        method: 'paybill',
        mpesaCode: 'QJK7H2LM4P',
        printCount: 1,
      ),
    ];
    final expectedNewPaymentsData = <v2.PaymentsData>[
      const v2.PaymentsData(
        id: pay1,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        receiptNumber: 'R-000001',
        shiftId: shift,
        receivedBy: admin,
        receivedAt: t,
        amount: 1200,
        method: 'cash',
        printCount: 1,
      ),
      const v2.PaymentsData(
        id: pay2,
        createdAt: later,
        updatedAt: later,
        deviceId: dev,
        receiptNumber: 'R-000002',
        shiftId: shift,
        receivedBy: admin,
        receivedAt: later,
        amount: 700,
        method: 'paybill',
        mpesaCode: 'QJK7H2LM4P',
        printCount: 1,
      ),
    ];

    // (id, created, stay, payment, kind, price, start, end, category, name)
    const charges = [
      ('ch-1', t, stayA, pay1, 'check_in', 700, t, paidB, deluxe, 'Deluxe'),
      ('ch-2', t, stayB, pay1, 'check_in', 500, t, paidB, normal, 'Normal'),
      (
        'ch-3',
        later,
        stayA,
        pay2,
        'extension',
        700,
        paidB,
        paidA,
        deluxe,
        'Deluxe',
      ),
    ];
    final oldStayChargesData = <v1.StayChargesData>[
      for (final (id, at, stay, pay, kind, price, start, end, _, _) in charges)
        v1.StayChargesData(
          id: id,
          createdAt: at,
          updatedAt: at,
          deviceId: dev,
          stayId: stay,
          paymentId: pay,
          kind: kind,
          nights: 1,
          pricePerNight: price,
          amount: price,
          periodStart: start,
          periodEnd: end,
        ),
    ];
    final expectedNewStayChargesData = <v2.StayChargesData>[
      for (final (id, at, stay, pay, kind, price, start, end, cat, name)
          in charges)
        v2.StayChargesData(
          id: id,
          createdAt: at,
          updatedAt: at,
          deviceId: dev,
          stayId: stay,
          paymentId: pay,
          kind: kind,
          nights: 1,
          pricePerNight: price,
          amount: price,
          periodStart: start,
          periodEnd: end,
          categoryId: cat,
          categoryName: name,
        ),
    ];

    final oldDeviceData = <v1.DeviceData>[
      const v1.DeviceData(deviceId: dev, createdAt: t),
    ];
    final expectedNewDeviceData = <v2.DeviceData>[
      const v2.DeviceData(deviceId: dev, createdAt: t),
    ];

    final oldReceiptCounterData = <v1.ReceiptCounterData>[
      const v1.ReceiptCounterData(deviceId: dev, nextNumber: 3),
    ];
    final expectedNewReceiptCounterData = <v2.ReceiptCounterData>[
      const v2.ReceiptCounterData(deviceId: dev, nextNumber: 3),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: open,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.users, oldUsersData);
        batch.insertAll(oldDb.settings, oldSettingsData);
        batch.insertAll(oldDb.bedCategories, oldBedCategoriesData);
        batch.insertAll(oldDb.rooms, oldRoomsData);
        batch.insertAll(oldDb.beds, oldBedsData);
        batch.insertAll(oldDb.guests, oldGuestsData);
        batch.insertAll(oldDb.shifts, oldShiftsData);
        batch.insertAll(oldDb.stays, oldStaysData);
        batch.insertAll(oldDb.payments, oldPaymentsData);
        batch.insertAll(oldDb.stayCharges, oldStayChargesData);
        batch.insertAll(oldDb.device, oldDeviceData);
        batch.insertAll(oldDb.receiptCounter, oldReceiptCounterData);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.users).get(), expectedNewUsersData);
        expect(
          await newDb.select(newDb.settings).get(),
          expectedNewSettingsData,
        );
        expect(
          await newDb.select(newDb.bedCategories).get(),
          expectedNewBedCategoriesData,
        );
        expect(await newDb.select(newDb.rooms).get(), expectedNewRoomsData);
        expect(await newDb.select(newDb.beds).get(), expectedNewBedsData);
        expect(await newDb.select(newDb.guests).get(), expectedNewGuestsData);
        expect(await newDb.select(newDb.shifts).get(), expectedNewShiftsData);
        expect(await newDb.select(newDb.stays).get(), expectedNewStaysData);
        expect(
          await newDb.select(newDb.payments).get(),
          expectedNewPaymentsData,
        );
        expect(
          await newDb.select(newDb.stayCharges).get(),
          expectedNewStayChargesData,
        );
        expect(await newDb.select(newDb.device).get(), expectedNewDeviceData);
        expect(
          await newDb.select(newDb.receiptCounter).get(),
          expectedNewReceiptCounterData,
        );
        // The rebuild is local: nothing is audited or queued for sync.
        expect(await newDb.select(newDb.auditLog).get(), isEmpty);
        expect(await newDb.select(newDb.outbox).get(), isEmpty);
      },
    );
  });

  group('upgrade safety', () {
    test('an upgraded file matches what this build creates (the startup '
        'check passes), with foreign keys back on and charges still never '
        'deleted', () async {
      // The verifier's v1 writes its SQL differently from the app, so this
      // uses the exact statements the v1 app ran (the snapshot's fixed_sql).
      final db = open(
        NativeDatabase.memory(
          setup: (raw) {
            v1AppStatements().forEach(raw.execute);
            raw.execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(db.close);
      final fresh = open(NativeDatabase.memory());
      addTearDown(fresh.close);

      expect(await schemaDifferences(db, fresh), isEmpty);
      final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(fk.read<int>('foreign_keys'), 1);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        2,
      );
      final triggers = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' "
            "AND tbl_name = 'stay_charges'",
          )
          .get();
      expect(
        {for (final r in triggers) r.read<String>('name')},
        {'stay_charges_stamped_update', 'stay_charges_no_delete'},
      );
    });

    test('a foreign key pointing nowhere after the steps undoes the whole '
        'upgrade', () async {
      final schema = await verifier.schemaAt(1);
      // A v1 file with a stay whose guest, bed and user don't exist (foreign
      // keys are off on the raw connection, as on an old file that had
      // them off).
      schema.rawDatabase.execute(
        'INSERT INTO stays (id, created_at, updated_at, device_id, guest_id, '
        'bed_id, check_in_at, paid_until, status, checked_in_by) VALUES '
        "('stay-x', '$t', '$t', 'd', 'no-guest', 'no-bed', '$t', '$later', "
        "'active', 'no-user')",
      );
      final db = open(schema.newConnection());
      addTearDown(db.close);

      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<MigrationFailed>()
              .having((e) => e.from, 'from', 1)
              .having((e) => e.problems.join(), 'problems', contains('stays')),
        ),
      );
      // Still v1: the version and the charges table are as they were.
      final raw = schema.rawDatabase;
      expect(raw.select('PRAGMA user_version').single['user_version'], 1);
      final columns = {
        for (final row in raw.select('PRAGMA table_info(stay_charges)'))
          row['name'] as String,
      };
      expect(columns, isNot(contains('category_id')));
      expect(columns, contains('price_per_night'));
    });

    test(
      'before upgrading, the file is copied to <file>.v1.bak as it was',
      () async {
        final dir = await Directory.systemTemp.createTemp('lodging_migrate');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}${Platform.pathSeparator}lodging_pos.sqlite';

        final schema = await verifier.schemaAt(1);
        schema.rawDatabase.execute(
          'INSERT INTO bed_categories (id, created_at, updated_at, device_id, '
          "name, price_per_night, sort_order, is_active) VALUES ('c1', '$t', "
          "'$t', 'seed', 'Deluxe', 700, 1, 1)",
        );
        schema.rawDatabase.execute("VACUUM INTO '$path'");

        final db = open(
          NativeDatabase(File(path)),
          beforeMigration: (db, from) => copyBeforeMigration(db, path, from),
        );
        expect(await db.select(db.bedCategories).get(), hasLength(1));
        await db.close();

        final backup = File('$path.v1.bak');
        expect(backup.existsSync(), isTrue);
        final copy = v1.DatabaseAtV1(NativeDatabase(backup));
        addTearDown(copy.close);
        expect(
          (await copy.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          1,
        );
        expect(
          (await copy.select(copy.bedCategories).getSingle()).name,
          'Deluxe',
        );
        final columns = await copy
            .customSelect('PRAGMA table_info(stay_charges)')
            .get();
        expect(
          columns.map((r) => r.read<String>('name')),
          isNot(contains('category_id')),
        );
      },
    );

    test('pre-migration copies: the newest two are kept, a repeated version '
        'is replaced', () async {
      final dir = await Directory.systemTemp.createTemp('lodging_backups');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}lodging_pos.sqlite';
      final db = open(NativeDatabase.memory());
      addTearDown(db.close);
      File('$path.bak-20261016-125228').writeAsStringSync('reset backup');

      for (final from in [1, 2, 3, 3]) {
        await copyBeforeMigration(db, path, from);
      }
      final names = {for (final f in dir.listSync()) f.uri.pathSegments.last};
      expect(names, {
        'lodging_pos.sqlite.v2.bak',
        'lodging_pos.sqlite.v3.bak',
        // A debug reset's backup is not a migration copy: never touched.
        'lodging_pos.sqlite.bak-20261016-125228',
      });
    });

    test('staleMigrationBackups keeps the two highest versions', () {
      expect(
        staleMigrationBackups('lodging_pos.sqlite', [
          'lodging_pos.sqlite',
          'lodging_pos.sqlite.v1.bak',
          'lodging_pos.sqlite.v10.bak',
          'lodging_pos.sqlite.v9.bak',
          'lodging_pos.sqlite.v2.bak',
          'lodging_pos.sqlite.v3.bak.partial',
          'other.sqlite.v1.bak',
        ]),
        unorderedEquals([
          'lodging_pos.sqlite.v1.bak',
          'lodging_pos.sqlite.v2.bak',
        ]),
      );
    });
  });
}
