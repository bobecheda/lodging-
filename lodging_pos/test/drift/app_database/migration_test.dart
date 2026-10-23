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
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  /// What the app's `createAll` ran at [version]: every table, index and
  /// trigger from that version's frozen snapshot SQL, in order.
  List<String> appStatements(int version) {
    final snapshot = jsonDecode(
      File('drift_schemas/app_database/drift_schema_v$version.json')
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

  test('migration from v1 to v5 keeps every row, gives each charge its '
      'bed’s category and each stay its room and bed', () async {
    final oldUsersData = <v1.UsersData>[
      const v1.UsersData(
        id: admin,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        fullName: 'Grace Supervisor',
        username: 'owner',
        passwordHash: 'not-a-real-hash',
        role: 'admin',
        isActive: 1,
        mustChangePassword: 0,
      ),
    ];
    final expectedNewUsersData = <v5.UsersData>[
      const v5.UsersData(
        id: admin,
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        fullName: 'Grace Supervisor',
        username: 'owner',
        passwordHash: 'not-a-real-hash',
        role: 'admin',
        isActive: 1,
        mustChangePassword: 0,
      ),
    ];

    // Every v1 key present; the upgrade adds only the keys created since,
    // at their default (backup_second_folder, daily backups).
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
    final expectedNewSettingsData = <v5.SettingsData>[
      for (final s in settings)
        v5.SettingsData(
          key: s.key,
          value: s.value,
          createdAt: t,
          updatedAt: t,
          deviceId: 'seed',
        ),
      // Stamped with the upgrade's clock (testT0).
      const v5.SettingsData(
        key: 'backup_second_folder',
        value: '',
        createdAt: '2026-10-14T19:00:00.000Z',
        updatedAt: '2026-10-14T19:00:00.000Z',
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
    final expectedNewBedCategoriesData = <v5.BedCategoriesData>[
      const v5.BedCategoriesData(
        id: deluxe,
        createdAt: t,
        updatedAt: t,
        deviceId: 'seed',
        name: 'Deluxe',
        pricePerNight: 700,
        sortOrder: 1,
        isActive: 1,
      ),
      const v5.BedCategoriesData(
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
    final expectedNewRoomsData = <v5.RoomsData>[
      const v5.RoomsData(
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
    final expectedNewBedsData = <v5.BedsData>[
      for (final (id, label, category) in const [
        (bedA, 'A', deluxe),
        (bedB, 'B', normal),
      ])
        v5.BedsData(
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
    final expectedNewGuestsData = <v5.GuestsData>[
      const v5.GuestsData(
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
    final expectedNewShiftsData = <v5.ShiftsData>[
      const v5.ShiftsData(
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
    // v3: room 7 and each stay's bed label, from the bed.
    final expectedNewStaysData = <v5.StaysData>[
      for (final (id, bed, paid, label) in const [
        (stayA, bedA, paidA, 'A'),
        (stayB, bedB, paidB, 'B'),
      ])
        v5.StaysData(
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
          roomNumber: '7',
          bedLabel: label,
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
    final expectedNewPaymentsData = <v5.PaymentsData>[
      const v5.PaymentsData(
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
      const v5.PaymentsData(
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
    final expectedNewStayChargesData = <v5.StayChargesData>[
      for (final (id, at, stay, pay, kind, price, start, end, cat, name)
          in charges)
        v5.StayChargesData(
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
    final expectedNewDeviceData = <v5.DeviceData>[
      const v5.DeviceData(deviceId: dev, createdAt: t),
    ];

    final oldReceiptCounterData = <v1.ReceiptCounterData>[
      const v1.ReceiptCounterData(deviceId: dev, nextNumber: 3),
    ];
    final expectedNewReceiptCounterData = <v5.ReceiptCounterData>[
      const v5.ReceiptCounterData(deviceId: dev, nextNumber: 3),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 5,
      createOld: v1.DatabaseAtV1.new,
      createNew: v5.DatabaseAtV5.new,
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

  test('migration from v3 to v4 keeps cleaning tasks, none cancelled, and '
      'still allows one open task per bed', () async {
    const user = v3.UsersData(
      id: admin,
      createdAt: t,
      updatedAt: t,
      deviceId: dev,
      fullName: 'Grace Supervisor',
      username: 'owner',
      passwordHash: 'not-a-real-hash',
      role: 'admin',
      isActive: 1,
      mustChangePassword: 0,
    );
    const category = v3.BedCategoriesData(
      id: deluxe,
      createdAt: t,
      updatedAt: t,
      deviceId: 'seed',
      name: 'Deluxe',
      pricePerNight: 700,
      sortOrder: 1,
      isActive: 1,
    );
    const roomRow = v3.RoomsData(
      id: room,
      createdAt: t,
      updatedAt: t,
      deviceId: dev,
      roomNumber: '7',
      isActive: 1,
    );
    final beds = [
      for (final (id, label) in const [(bedA, 'A'), (bedB, 'B')])
        v3.BedsData(
          id: id,
          createdAt: t,
          updatedAt: t,
          deviceId: dev,
          roomId: room,
          label: label,
          categoryId: deluxe,
          cleanliness: label == 'A' ? 'not_cleaned' : 'clean',
          isActive: 1,
        ),
    ];
    const rose = v3.HousekeepersData(
      id: 'hk-rose',
      createdAt: t,
      updatedAt: t,
      deviceId: dev,
      fullName: 'Rose Akinyi',
      isActive: 1,
    );
    // An open task on Bed A; a finished one on Bed B.
    const oldTasks = [
      v3.HousekeepingTasksData(
        id: 'task-open',
        createdAt: t,
        updatedAt: t,
        deviceId: dev,
        bedId: bedA,
        housekeeperId: 'hk-rose',
        assignedBy: admin,
        assignedAt: t,
      ),
      v3.HousekeepingTasksData(
        id: 'task-done',
        createdAt: t,
        updatedAt: later,
        deviceId: dev,
        bedId: bedB,
        housekeeperId: 'hk-rose',
        assignedBy: admin,
        assignedAt: t,
        completedAt: later,
        completedBy: admin,
      ),
    ];
    final expectedTasks = [
      for (final o in oldTasks)
        v4.HousekeepingTasksData(
          id: o.id,
          createdAt: o.createdAt,
          updatedAt: o.updatedAt,
          deviceId: o.deviceId,
          bedId: o.bedId,
          housekeeperId: o.housekeeperId,
          assignedBy: o.assignedBy,
          assignedAt: o.assignedAt,
          completedAt: o.completedAt,
          completedBy: o.completedBy,
        ),
    ];

    await verifier.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 4,
      createOld: v3.DatabaseAtV3.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: open,
      createItems: (batch, oldDb) {
        batch.insert(oldDb.users, user);
        batch.insert(oldDb.bedCategories, category);
        batch.insert(oldDb.rooms, roomRow);
        batch.insertAll(oldDb.beds, beds);
        batch.insert(oldDb.housekeepers, rose);
        batch.insertAll(oldDb.housekeepingTasks, oldTasks);
      },
      validateItems: (newDb) async {
        final tasks = await (newDb.select(
          newDb.housekeepingTasks,
        )..orderBy([(x) => OrderingTerm.asc(x.id)])).get();
        expect(tasks, [expectedTasks.last, expectedTasks.first]);
        expect(tasks.every((x) => x.cancelledAt == null), isTrue);
        // Still one open task per bed: a second open one on Bed A fails.
        await expectLater(
          newDb.customStatement(
            'INSERT INTO housekeeping_tasks (id, created_at, updated_at, '
            'device_id, bed_id, housekeeper_id, assigned_by, assigned_at) '
            "VALUES ('task-2', '$t', '$t', '$dev', '$bedA', 'hk-rose', "
            "'$admin', '$t')",
          ),
          throwsA(anything),
        );
      },
    );
  });

  test('migration from v4 to v5: a closed shift gets its count and closer, '
      'an open one stays empty; afterwards a closed shift never changes', () async {
    const deskUser = 'user-desk';
    final users = [
      for (final (id, name, role) in const [
        (admin, 'owner', 'admin'),
        (deskUser, 'mary', 'receptionist'),
      ])
        v4.UsersData(
          id: id,
          createdAt: t,
          updatedAt: t,
          deviceId: dev,
          fullName: name,
          username: name,
          passwordHash: 'not-a-real-hash',
          role: role,
          isActive: 1,
          mustChangePassword: 0,
        ),
    ];
    // Mary's shift closed KES 200 short; the owner's shift still open.
    const closed = v4.ShiftsData(
      id: 'shift-closed',
      createdAt: t,
      updatedAt: later,
      deviceId: dev,
      userId: deskUser,
      openedAt: t,
      openingFloat: 1000,
      closedAt: later,
      expectedCash: 5000,
      expectedPaybill: 1400,
      countedCash: 4800,
      variance: -200,
      status: 'closed',
    );
    const stillOpen = v4.ShiftsData(
      id: 'shift-open',
      createdAt: later,
      updatedAt: later,
      deviceId: dev,
      userId: admin,
      openedAt: later,
      openingFloat: 0,
      status: 'open',
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 4,
      newVersion: 5,
      createOld: v4.DatabaseAtV4.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: open,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.users, users);
        batch.insertAll(oldDb.shifts, const [closed, stillOpen]);
      },
      validateItems: (newDb) async {
        final shifts = await (newDb.select(
          newDb.shifts,
        )..orderBy([(x) => OrderingTerm.asc(x.id)])).get();
        expect(shifts, const [
          v5.ShiftsData(
            id: 'shift-closed',
            createdAt: t,
            updatedAt: later,
            deviceId: dev,
            userId: deskUser,
            openedAt: t,
            openingFloat: 1000,
            closedAt: later,
            expectedCash: 5000,
            expectedPaybill: 1400,
            countedCash: 4800,
            variance: -200,
            status: 'closed',
            firstCount: 4800,
            closedBy: deskUser,
          ),
          v5.ShiftsData(
            id: 'shift-open',
            createdAt: later,
            updatedAt: later,
            deviceId: dev,
            userId: admin,
            openedAt: later,
            openingFloat: 0,
            status: 'open',
          ),
        ]);
        // The v5 trigger: a closed shift can't be reopened or changed.
        await expectLater(
          newDb.customStatement(
            "UPDATE shifts SET status = 'open', closed_at = NULL, "
            "updated_at = '2030-01-01T00:00:00.000Z' WHERE id = 'shift-closed'",
          ),
          throwsA(anything),
        );
      },
    );
  });

  test(
    'migration from v5 to v6: the admin becomes the supervisor, nothing '
    'else about the users changes; owner is allowed, admin no longer',
    () async {
      const deskUser = 'user-desk';
      final users = [
        for (final (id, name, role) in const [
          (admin, 'grace', 'admin'),
          (deskUser, 'mary', 'receptionist'),
        ])
          v5.UsersData(
            id: id,
            createdAt: t,
            updatedAt: later,
            deviceId: dev,
            fullName: name,
            username: name,
            passwordHash: 'not-a-real-hash',
            role: role,
            isActive: 1,
            mustChangePassword: 0,
          ),
      ];

      await verifier.testWithDataIntegrity(
        oldVersion: 5,
        newVersion: 6,
        createOld: v5.DatabaseAtV5.new,
        createNew: v6.DatabaseAtV6.new,
        openTestedDatabase: open,
        createItems: (batch, oldDb) => batch.insertAll(oldDb.users, users),
        validateItems: (newDb) async {
          final rows = await (newDb.select(
            newDb.users,
          )..orderBy([(x) => OrderingTerm.asc(x.id)])).get();
          // Same timestamps: the rebuild copies rows, no UPDATE runs.
          expect(rows, [
            for (final (id, name, role) in const [
              (admin, 'grace', 'supervisor'),
              (deskUser, 'mary', 'receptionist'),
            ])
              v6.UsersData(
                id: id,
                createdAt: t,
                updatedAt: later,
                deviceId: dev,
                fullName: name,
                username: name,
                passwordHash: 'not-a-real-hash',
                role: role,
                isActive: 1,
                mustChangePassword: 0,
              ),
          ]);
          Future<void> insert(String id, String role) => newDb.customStatement(
            'INSERT INTO users (id, created_at, updated_at, device_id, '
            'full_name, username, password_hash, role, is_active, '
            'must_change_password) '
            "VALUES ('$id', '$t', '$t', '$dev', '$id', '$id', 'x', '$role', "
            '1, 0)',
          );
          await insert('amina', 'owner');
          await expectLater(insert('old', 'admin'), throwsA(anything));
          // The users' trigger is back after the rebuild.
          await expectLater(
            newDb.customStatement(
              "UPDATE users SET full_name = 'x' WHERE id = '$deskUser'",
            ),
            throwsA(anything),
          );
        },
      );
    },
  );

  test('migration from v6 to v7: an M-Pesa payout gets its guest\'s phone, '
      'a cash one none; afterwards the phone is required for M-Pesa and '
      'never changes once paid', () async {
    const t6 = '2026-10-21T06:00:00.000Z';
    const t7 = '2026-10-21T07:00:00.000Z';
    String row(String table, Map<String, Object?> values) {
      final cols = values.keys.join(', ');
      final vals = [
        for (final v in values.values)
          v == null
              ? 'NULL'
              : v is int
              ? '$v'
              : "'$v'",
      ].join(', ');
      return 'INSERT INTO $table ($cols) VALUES ($vals)';
    }

    Map<String, Object?> synced(String id) => {
      'id': id,
      'created_at': t6,
      'updated_at': t6,
      'device_id': dev,
    };
    final db = open(
      NativeDatabase.memory(
        setup: (raw) {
          appStatements(6).forEach(raw.execute);
          raw.execute('PRAGMA user_version = 6');
          for (final sql in [
            row('users', {
              ...synced('u1'),
              'full_name': 'Mary',
              'username': 'mary',
              'password_hash': 'x',
              'role': 'receptionist',
              'is_active': 1,
              'must_change_password': 0,
            }),
            row('guests', {
              ...synced('g1'),
              'full_name': 'Peter Kamau',
              'phone': '0711000482',
            }),
            row('bed_categories', {
              ...synced('c1'),
              'name': 'Deluxe',
              'price_per_night': 700,
              'sort_order': 1,
            }),
            row('rooms', {...synced('r1'), 'room_number': '5'}),
            for (final (id, label) in [('b1', 'A'), ('b2', 'B')])
              row('beds', {
                ...synced(id),
                'room_id': 'r1',
                'label': label,
                'category_id': 'c1',
                'cleanliness': 'not_cleaned',
              }),
            row('shifts', {
              ...synced('s1'),
              'user_id': 'u1',
              'opened_at': t6,
              'opening_float': 0,
              'status': 'open',
            }),
            for (final (stay, bed, label) in [
              ('st1', 'b1', 'A'),
              ('st2', 'b2', 'B'),
            ])
              row('stays', {
                ...synced(stay),
                'guest_id': 'g1',
                'bed_id': bed,
                'check_in_at': t6,
                'paid_until': t6,
                'checked_out_at': t6,
                'status': 'closed',
                'checked_in_by': 'u1',
                'checked_out_by': 'u1',
                'room_number': '5',
                'bed_label': label,
              }),
            for (final (refund, stay) in [('rf1', 'st1'), ('rf2', 'st2')]) ...[
              row('refunds', {
                ...synced(refund),
                'stay_id': stay,
                'nights': 2,
                'price_per_night': 700,
                'amount': 1400,
                'requested_by': 'u1',
                'requested_at': t6,
              }),
              row('refund_decisions', {
                ...synced('d-$refund'),
                'refund_id': refund,
                'decision': 'approved',
                'decided_by': 'u1',
                'decided_at': t6,
              }),
            ],
            // Paid before v7, through the triggers (approved first).
            "UPDATE refunds SET method = 'paybill', mpesa_code = 'QJK7H2LM4P', "
                "shift_id = 's1', paid_by = 'u1', paid_at = '$t6', "
                "receipt_number = 'R-000009', updated_at = '$t7' "
                "WHERE id = 'rf1'",
            "UPDATE refunds SET method = 'cash', shift_id = 's1', "
                "paid_by = 'u1', paid_at = '$t6', receipt_number = 'R-000010', "
                "updated_at = '$t7' WHERE id = 'rf2'",
          ]) {
            raw.execute(sql);
          }
        },
      ),
    );
    addTearDown(db.close);

    final refunds = await db
        .customSelect(
          'SELECT id, payout_phone, updated_at FROM refunds ORDER BY id',
        )
        .get();
    expect(
      [
        for (final r in refunds)
          (
            r.read<String>('id'),
            r.readNullable<String>('payout_phone'),
            r.read<String>('updated_at'),
          ),
      ],
      [('rf1', '0711000482', t7), ('rf2', null, t7)],
    );
    // The new trigger: a paid refund's phone never changes.
    await expectLater(
      db.customStatement(
        "UPDATE refunds SET payout_phone = '0700000000', "
        "updated_at = '2030-01-01T00:00:00.000Z' WHERE id = 'rf1'",
      ),
      throwsA(anything),
    );
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      9,
    );
  });

  test('migration from v7 to v8: the price request tables start empty, '
      'the prices are untouched, and one request per category stays '
      'open', () async {
    const t7 = '2026-10-22T06:00:00.000Z';
    const t8 = '2026-10-22T07:00:00.000Z';
    Map<String, Object?> synced(String id, [String at = t7]) => {
      'id': id,
      'created_at': at,
      'updated_at': at,
      'device_id': dev,
    };
    String insert(String table, Map<String, Object?> values) =>
        'INSERT INTO $table (${values.keys.join(', ')}) VALUES (${[for (final v in values.values) v == null
              ? 'NULL'
              : v is int
              ? '$v'
              : "'$v'"].join(', ')})';
    final db = open(
      NativeDatabase.memory(
        setup: (raw) {
          appStatements(7).forEach(raw.execute);
          raw.execute('PRAGMA user_version = 7');
          raw.execute(
            insert('users', {
              ...synced('u1'),
              'full_name': 'Grace Supervisor',
              'username': 'grace',
              'password_hash': 'x',
              'role': 'supervisor',
              'is_active': 1,
              'must_change_password': 0,
            }),
          );
          raw.execute(
            insert('bed_categories', {
              ...synced('c1'),
              'name': 'Deluxe',
              'price_per_night': 700,
              'sort_order': 1,
            }),
          );
        },
      ),
    );
    addTearDown(db.close);

    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      9,
    );
    final category = await db
        .customSelect('SELECT price_per_night, updated_at FROM bed_categories')
        .getSingle();
    expect(
      (
        category.read<int>('price_per_night'),
        category.read<String>('updated_at'),
      ),
      (700, t7),
    );
    for (final table in ['price_requests', 'price_decisions']) {
      final count = await db
          .customSelect('SELECT count(*) AS n FROM $table')
          .getSingle();
      expect(count.read<int>('n'), 0, reason: table);
    }

    Map<String, Object?> request(String id) => {
      ...synced(id, t8),
      'category_id': 'c1',
      'old_price': 700,
      'new_price': 750,
      'requested_by': 'u1',
      'requested_at': t8,
    };
    await db.customStatement(insert('price_requests', request('p1')));
    // The new trigger: one open request per category.
    await expectLater(
      db.customStatement(insert('price_requests', request('p2'))),
      throwsA(
        predicate(
          (e) => '$e'.contains(
            'the category already has an open price '
            'request',
          ),
        ),
      ),
    );
  });

  test('migration from v8 to v9: the sync bookkeeping starts empty (not '
      'connected); the outbox is untouched', () async {
    final db = open(
      NativeDatabase.memory(
        setup: (raw) {
          appStatements(8).forEach(raw.execute);
          raw.execute('PRAGMA user_version = 8');
          raw.execute(
            "INSERT INTO outbox (target_table, target_row_id, payload_json, "
            "created_at) VALUES ('rooms', 'r1', '{}', "
            "'2026-10-22T06:00:00.000Z')",
          );
        },
      ),
    );
    addTearDown(db.close);
    expect(await db.select(db.syncState).get(), isEmpty);
    final outbox = await db.select(db.outbox).getSingle();
    expect((outbox.targetRowId, outbox.sentAt), ('r1', null));
  });

  group('upgrade safety', () {
    for (final from in [1, 2, 3, 4, 5, 6, 7, 8]) {
      test('an upgraded v$from file matches what this build creates (the '
          'startup check passes), with foreign keys back on and the rebuilt '
          'tables keeping their triggers and indexes', () async {
        // The verifier writes its SQL differently from the app, so this uses
        // the exact statements that version of the app ran (fixed_sql).
        final db = open(
          NativeDatabase.memory(
            setup: (raw) {
              appStatements(from).forEach(raw.execute);
              raw.execute('PRAGMA user_version = $from');
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
          9,
        );
        final objects = await db
            .customSelect(
              'SELECT name FROM sqlite_master '
              "WHERE tbl_name IN ('stay_charges', 'stays', 'users') "
              "AND type IN ('trigger', 'index') AND sql IS NOT NULL",
            )
            .get();
        expect(
          {for (final r in objects) r.read<String>('name')},
          {
            'users_stamped_update',
            'stay_charges_stamped_update',
            'stay_charges_no_delete',
            'stay_charges_stay',
            'stay_charges_payment',
            'stays_stamped_update',
            'stays_no_delete',
            'stays_guest',
            'stays_one_active_per_bed',
          },
        );
      });
    }

    test('a foreign key pointing nowhere after the steps undoes the whole '
        'upgrade', () async {
      final schema = await verifier.schemaAt(1);
      // A v1 file with a payment whose shift and user don't exist (foreign
      // keys are off on the raw connection, as on an old file that had
      // them off). No step reads payments, so only the final check sees it.
      schema.rawDatabase.execute(
        'INSERT INTO payments (id, created_at, updated_at, device_id, '
        'receipt_number, shift_id, received_by, received_at, amount, method, '
        "print_count) VALUES ('pay-x', '$t', '$t', 'd', 'R-000009', "
        "'no-shift', 'no-user', '$t', 700, 'cash', 0)",
      );
      final db = open(schema.newConnection());
      addTearDown(db.close);

      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<MigrationFailed>()
              .having((e) => e.from, 'from', 1)
              .having(
                (e) => e.problems.join(),
                'problems',
                contains('payments'),
              ),
        ),
      );
      // Still v1: the version and the rebuilt tables are as they were.
      final raw = schema.rawDatabase;
      expect(raw.select('PRAGMA user_version').single['user_version'], 1);
      Set<String> columns(String table) => {
        for (final row in raw.select('PRAGMA table_info($table)'))
          row['name'] as String,
      };
      expect(columns('stay_charges'), isNot(contains('category_id')));
      expect(columns('stays'), isNot(contains('room_number')));
    });

    test('a stay whose bed is gone can’t be filled in: the upgrade fails '
        'and is undone', () async {
      final schema = await verifier.schemaAt(1);
      schema.rawDatabase.execute(
        'INSERT INTO stays (id, created_at, updated_at, device_id, guest_id, '
        'bed_id, check_in_at, paid_until, status, checked_in_by) VALUES '
        "('stay-x', '$t', '$t', 'd', 'no-guest', 'no-bed', '$t', '$later', "
        "'active', 'no-user')",
      );
      final db = open(schema.newConnection());
      addTearDown(db.close);
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
      final raw = schema.rawDatabase;
      expect(raw.select('PRAGMA user_version').single['user_version'], 1);
      expect(
        raw.select('PRAGMA table_info(stay_charges)').map((r) => r['name']),
        isNot(contains('category_id')),
      );
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
