import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:uuid/uuid.dart';

Matcher _violates(String constraint) => throwsA(
  predicate(
    (e) => e.toString().contains('$constraint constraint failed'),
    '$constraint constraint failure',
  ),
);

void main() {
  // 22:00 Nairobi.
  final t0 = DateTime.utc(2026, 10, 14, 19);
  late AppDatabase db;
  late String deviceId;

  // The reopen test opens extra instances, each on its own executor.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), clock: FixedClock(t0));
    deviceId = await db.deviceId();
  });

  tearDown(() => db.close());

  String newId() => const Uuid().v4();

  // Direct inserts to test constraints, so they pass the stamped columns
  // explicitly. App code writes through writeWithAudit.

  Future<String> user({String username = 'jane', String role = 'admin'}) async {
    final id = newId();
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: Value(id),
            createdAt: Value(t0),
            updatedAt: Value(t0),
            deviceId: Value(deviceId),
            fullName: 'Jane Doe',
            username: username,
            passwordHash: 'hash',
            role: role,
            mustChangePassword: false,
          ),
        );
    return id;
  }

  Future<String> room(String number) async {
    final id = newId();
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            id: Value(id),
            createdAt: Value(t0),
            updatedAt: Value(t0),
            deviceId: Value(deviceId),
            roomNumber: number,
          ),
        );
    return id;
  }

  Future<String> bed(
    String roomId, {
    String label = 'A',
    String? categoryId,
  }) async {
    final id = newId();
    await db
        .into(db.beds)
        .insert(
          BedsCompanion.insert(
            id: Value(id),
            createdAt: Value(t0),
            updatedAt: Value(t0),
            deviceId: Value(deviceId),
            roomId: roomId,
            label: label,
            categoryId: categoryId ?? SeedIds.deluxe,
            cleanliness: 'clean',
          ),
        );
    return id;
  }

  Future<String> guest({String? idType, String? idNumber}) async {
    final id = newId();
    await db
        .into(db.guests)
        .insert(
          GuestsCompanion.insert(
            id: Value(id),
            createdAt: Value(t0),
            updatedAt: Value(t0),
            deviceId: Value(deviceId),
            fullName: 'John Guest',
            phone: '0712345678',
            idType: Value(idType),
            idNumber: Value(idNumber),
          ),
        );
    return id;
  }

  Future<String> shift(
    String userId, {
    bool closed = false,
    int counted = 1000,
    int? variance,
  }) async {
    final id = newId();
    await db
        .into(db.shifts)
        .insert(
          ShiftsCompanion.insert(
            id: Value(id),
            createdAt: Value(t0),
            updatedAt: Value(t0),
            deviceId: Value(deviceId),
            userId: userId,
            openedAt: t0,
            openingFloat: 1000,
            status: closed ? 'closed' : 'open',
            closedAt: Value(closed ? t0.add(const Duration(hours: 8)) : null),
            expectedCash: Value(closed ? 1000 : null),
            expectedPaybill: Value(closed ? 0 : null),
            countedCash: Value(closed ? counted : null),
            variance: Value(closed ? variance ?? counted - 1000 : null),
          ),
        );
    return id;
  }

  Future<String> stay(
    String guestId,
    String bedId,
    String userId, {
    bool closed = false,
  }) async {
    final id = newId();
    await db
        .into(db.stays)
        .insert(
          StaysCompanion.insert(
            id: Value(id),
            createdAt: Value(t0),
            updatedAt: Value(t0),
            deviceId: Value(deviceId),
            guestId: guestId,
            bedId: bedId,
            checkInAt: t0,
            paidUntil: t0.add(const Duration(hours: 12)),
            status: closed ? 'closed' : 'active',
            checkedOutAt: Value(
              closed ? t0.add(const Duration(hours: 1)) : null,
            ),
            checkedInBy: userId,
            checkedOutBy: Value(closed ? userId : null),
          ),
        );
    return id;
  }

  Future<String> payment(
    String shiftId,
    String userId, {
    required String receipt,
    String method = 'cash',
    String? mpesaCode,
  }) async {
    final id = newId();
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            id: Value(id),
            createdAt: Value(t0),
            updatedAt: Value(t0),
            deviceId: Value(deviceId),
            receiptNumber: receipt,
            shiftId: shiftId,
            receivedBy: userId,
            receivedAt: t0,
            amount: 700,
            method: method,
            mpesaCode: Value(mpesaCode),
          ),
        );
    return id;
  }

  Future<void> charge(
    String stayId,
    String paymentId, {
    int nights = 1,
    int pricePerNight = 700,
    String kind = 'check_in',
    int? amount,
  }) => db
      .into(db.stayCharges)
      .insert(
        StayChargesCompanion.insert(
          id: Value(newId()),
          createdAt: Value(t0),
          updatedAt: Value(t0),
          deviceId: Value(deviceId),
          stayId: stayId,
          paymentId: paymentId,
          kind: kind,
          nights: nights,
          pricePerNight: pricePerNight,
          amount: amount ?? nights * pricePerNight,
          periodStart: t0,
          periodEnd: t0.add(Duration(days: nights < 1 ? 1 : nights)),
          categoryId: SeedIds.deluxe,
          categoryName: 'Deluxe',
        ),
      );

  group('durability: WAL with synchronous FULL', () {
    Future<Object?> pragma(AppDatabase d, String name) async =>
        (await d.customSelect('PRAGMA $name').getSingle()).data.values.single;

    test('a database file opens in WAL mode with synchronous FULL (2), '
        'on creation and on every later open', () async {
      final dir = await Directory.systemTemp.createTemp('lodging_wal');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}db.sqlite');
      for (var open = 0; open < 2; open++) {
        final d = AppDatabase(NativeDatabase(file), clock: FixedClock(t0));
        expect(await pragma(d, 'journal_mode'), 'wal');
        expect(await pragma(d, 'synchronous'), 2);
        expect(await pragma(d, 'foreign_keys'), 1);
        await d.close();
      }
    });

    test('in memory, synchronous is FULL too', () async {
      expect(await pragma(db, 'synchronous'), 2);
    });
  });

  group('seed', () {
    test(
      'creates exactly one device and a receipt counter starting at 1',
      () async {
        final devices = await db.select(db.device).get();
        expect(devices, hasLength(1));
        expect(devices.single.deviceId, deviceId);
        expect(Uuid.isValidUUID(fromString: deviceId), isTrue);
        expect(devices.single.createdAt, t0);

        final counter = await db.select(db.receiptCounter).getSingle();
        expect(counter.deviceId, deviceId);
        expect(counter.nextNumber, 1);
      },
    );

    test('creates the settings keys', () async {
      final rows = await db.select(db.settings).get();
      expect(
        {for (final r in rows) r.key: r.value},
        {
          'lodging_name': '',
          'checkout_time': '10:00',
          'grace_minutes': '60',
          'receipt_prefix': 'R',
          'idle_lock_minutes': '10',
        },
      );
      for (final r in rows) {
        expect(r.updatedBy, isNull);
        expect(r.deviceId, seedDeviceId);
        expect(r.createdAt, t0);
        expect(r.createdAt.isUtc, isTrue);
      }
    });

    test('creates the four bed categories with fixed ids (BR-2)', () async {
      final rows = await (db.select(
        db.bedCategories,
      )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();
      expect(
        [for (final r in rows) (r.id, r.name, r.pricePerNight, r.isActive)],
        [
          (SeedIds.vip, 'VIP', 1000, true),
          (SeedIds.deluxe, 'Deluxe', 700, true),
          (SeedIds.comfort, 'Comfort', 600, true),
          (SeedIds.normal, 'Normal', 500, true),
        ],
      );
    });

    test('creates no users, audit entries or outbox rows', () async {
      expect(await db.select(db.users).get(), isEmpty);
      expect(await db.select(db.auditLog).get(), isEmpty);
      expect(await db.select(db.outbox).get(), isEmpty);
    });

    test('runs only once, and the device id survives a reopen', () async {
      final dir = Directory.systemTemp.createTempSync('lodging_pos_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}db.sqlite');

      final first = AppDatabase(NativeDatabase(file), clock: FixedClock(t0));
      addTearDown(first.close);
      final firstId = await first.deviceId();
      await first.close();

      final second = AppDatabase(NativeDatabase(file), clock: FixedClock(t0));
      addTearDown(second.close);
      expect(await second.deviceId(), firstId);
      expect(await second.select(second.device).get(), hasLength(1));
      expect(await second.select(second.bedCategories).get(), hasLength(4));
      await second.close();
    });
  });

  group('bed_categories (AD-3)', () {
    Future<int> category(String name, {int price = 800}) => db
        .into(db.bedCategories)
        .insert(
          BedCategoriesCompanion.insert(
            id: Value(newId()),
            createdAt: Value(t0),
            updatedAt: Value(t0),
            deviceId: Value(deviceId),
            name: name,
            pricePerNight: price,
            sortOrder: 9,
          ),
        );

    test('names are unique ignoring case', () async {
      await expectLater(category('deluxe'), _violates('UNIQUE'));
      await expectLater(category('VIP'), _violates('UNIQUE'));
      await category('Family');
    });

    test('names are stored trimmed, 1–30 characters', () async {
      await expectLater(category(' Family'), _violates('CHECK'));
      await expectLater(category(''), _violates('CHECK'));
      await expectLater(category('x' * 31), _violates('CHECK'));
      await category('x' * 30);
    });

    test('price per night is 1–100,000', () async {
      await expectLater(category('A', price: 0), _violates('CHECK'));
      await expectLater(category('B', price: 100001), _violates('CHECK'));
      await category('C', price: 100000);
    });
  });

  group('integrity', () {
    test('foreign keys are enforced', () async {
      final pragma = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(pragma.data.values.single, 1);
      await expectLater(bed('no-such-room'), _violates('FOREIGN KEY'));
    });

    test('seed data passes the foreign key check', () async {
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test('timestamps round-trip as UTC', () async {
      final r = await db.select(db.device).getSingle();
      expect(r.createdAt.isUtc, isTrue);
      expect(r.createdAt, t0);
    });
  });

  group('users', () {
    test('username is stored trimmed and lowercase, and unique', () async {
      await user(username: 'jane');
      await expectLater(user(username: 'jane'), _violates('UNIQUE'));
      await expectLater(user(username: 'JANE'), _violates('CHECK'));
      await expectLater(user(username: ' jane2'), _violates('CHECK'));
    });

    test('role must be admin or receptionist', () async {
      await expectLater(user(role: 'owner'), _violates('CHECK'));
    });
  });

  group('beds', () {
    test('label must be A or B, unique within a room', () async {
      final r = await room('3');
      await bed(r, label: 'A');
      await bed(r, label: 'B');
      await expectLater(bed(r, label: 'A'), _violates('UNIQUE'));
      await expectLater(bed(r, label: 'C'), _violates('CHECK'));
    });
  });

  group('guests', () {
    test('ID pair is unique when an ID number is set', () async {
      await guest(idType: 'national_id', idNumber: '12345678');
      await expectLater(
        guest(idType: 'national_id', idNumber: '12345678'),
        _violates('UNIQUE'),
      );
      // Same number, different type is a different document.
      await guest(idType: 'passport', idNumber: '12345678');
    });

    test('many guests may have no ID', () async {
      await guest();
      await guest();
      expect(await db.select(db.guests).get(), hasLength(2));
    });

    test('ID number requires an ID type', () async {
      await expectLater(guest(idNumber: '12345678'), _violates('CHECK'));
    });

    test('ID pair is unique ignoring case', () async {
      await guest(idType: 'passport', idNumber: 'ak123456');
      await expectLater(
        guest(idType: 'passport', idNumber: 'AK123456'),
        _violates('UNIQUE'),
      );
    });

    test('type-ahead prefix search uses the phone and ID indexes', () async {
      Future<String> plan(String where) async =>
          (await db
                  .customSelect(
                    'EXPLAIN QUERY PLAN SELECT id FROM guests $where',
                  )
                  .get())
              .map((r) => r.read<String>('detail'))
              .join(' | ');
      expect(await plan("WHERE phone LIKE '0712%'"), contains('guests_phone'));
      expect(
        await plan("WHERE id_number LIKE 'AK12%'"),
        contains('guests_id_number'),
      );
    });
  });

  group('shifts', () {
    test('at most one open shift per device', () async {
      final u = await user();
      await shift(u, closed: true);
      await shift(u);
      await expectLater(shift(u), _violates('UNIQUE'));
    });

    test(
      'a closed shift needs its cash-up and variance = counted - expected',
      () async {
        final u = await user();
        await shift(u, closed: true, counted: 900); // variance -100
        await expectLater(
          shift(u, closed: true, counted: 900, variance: 0),
          _violates('CHECK'),
        );
        await expectLater(
          db
              .into(db.shifts)
              .insert(
                ShiftsCompanion.insert(
                  id: Value(newId()),
                  createdAt: Value(t0),
                  updatedAt: Value(t0),
                  deviceId: Value(deviceId),
                  userId: u,
                  openedAt: t0,
                  openingFloat: 1000,
                  status: 'closed',
                  closedAt: Value(t0.add(const Duration(hours: 8))),
                ),
              ),
          _violates('CHECK'),
        );
      },
    );
  });

  group('stays (BR-4)', () {
    test('one active stay per bed', () async {
      final u = await user();
      final b = await bed(await room('3'));
      final g = await guest();
      await stay(g, b, u, closed: true);
      await stay(g, b, u);
      await expectLater(stay(g, b, u), _violates('UNIQUE'));
    });

    test('checked_out_by is set exactly when the stay is closed', () async {
      final u = await user();
      final s = await stay(await guest(), await bed(await room('3')), u);
      // Moves updated_at so the stamped-update trigger lets it reach the CHECK.
      Future<int> write(StaysCompanion c) =>
          (db.update(db.stays)..where((t) => t.id.equals(s))).write(
            c.copyWith(updatedAt: Value(t0.add(const Duration(hours: 2)))),
          );

      await expectLater(
        write(
          StaysCompanion(
            status: const Value('closed'),
            checkedOutAt: Value(t0.add(const Duration(hours: 1))),
          ),
        ),
        _violates('CHECK'),
      );
      await expectLater(
        write(StaysCompanion(checkedOutBy: Value(u))),
        _violates('CHECK'),
      );
    });
  });

  group('housekeeping_tasks', () {
    test('at most one open task per bed', () async {
      final u = await user();
      final b = await bed(await room('3'));
      final hk = newId();
      await db
          .into(db.housekeepers)
          .insert(
            HousekeepersCompanion.insert(
              id: Value(hk),
              createdAt: Value(t0),
              updatedAt: Value(t0),
              deviceId: Value(deviceId),
              fullName: 'Mary',
            ),
          );
      Future<int> assign({bool completed = false}) => db
          .into(db.housekeepingTasks)
          .insert(
            HousekeepingTasksCompanion.insert(
              id: Value(newId()),
              createdAt: Value(t0),
              updatedAt: Value(t0),
              deviceId: Value(deviceId),
              bedId: b,
              housekeeperId: hk,
              assignedBy: u,
              assignedAt: t0,
              completedAt: Value(completed ? t0 : null),
              completedBy: Value(completed ? u : null),
            ),
          );
      await assign(completed: true);
      await assign();
      await expectLater(assign(), _violates('UNIQUE'));
    });
  });

  group('payments (BR-10)', () {
    late String u;
    late String s;

    setUp(() async {
      u = await user();
      s = await shift(u);
    });

    test('paybill requires an M-Pesa code', () async {
      await expectLater(
        payment(s, u, receipt: 'R-000001', method: 'paybill'),
        _violates('CHECK'),
      );
    });

    test('cash must not have an M-Pesa code', () async {
      await expectLater(
        payment(s, u, receipt: 'R-000001', mpesaCode: 'SJK4H7XQ2P'),
        _violates('CHECK'),
      );
    });

    test('an M-Pesa code can be used once, ignoring case', () async {
      await payment(
        s,
        u,
        receipt: 'R-000001',
        method: 'paybill',
        mpesaCode: 'SJK4H7XQ2P',
      );
      await expectLater(
        payment(
          s,
          u,
          receipt: 'R-000002',
          method: 'paybill',
          mpesaCode: 'sjk4h7xq2p',
        ),
        _violates('UNIQUE'),
      );
    });

    test('receipt numbers are unique', () async {
      await payment(s, u, receipt: 'R-000001');
      await expectLater(
        payment(s, u, receipt: 'R-000001'),
        _violates('UNIQUE'),
      );
    });
  });

  group('stay_charges', () {
    late String st;
    late String p;

    setUp(() async {
      final u = await user();
      st = await stay(await guest(), await bed(await room('3')), u);
      p = await payment(await shift(u), u, receipt: 'R-000001');
    });

    test('amount must equal nights × price_per_night', () async {
      await charge(st, p, nights: 2);
      await expectLater(
        charge(st, p, nights: 2, amount: 1000),
        _violates('CHECK'),
      );
    });

    test('nights must be at least 1', () async {
      await expectLater(charge(st, p, nights: 0), _violates('CHECK'));
    });

    test('kind is check_in, extension or late_checkout', () async {
      for (final kind in ['check_in', 'extension', 'late_checkout']) {
        await charge(st, p, kind: kind);
      }
      await expectLater(charge(st, p, kind: 'renewal'), _violates('CHECK'));
    });
  });

  group('refunds (BR-8, BR-8a, BR-8b)', () {
    late String u;
    late String s;
    late String st;
    var tick = 0;

    setUp(() async {
      u = await user();
      s = await shift(u);
      st = await stay(
        await guest(),
        await bed(await room('3')),
        u,
        closed: true,
      );
    });

    Future<String> refund({
      String? stayId,
      int nights = 3,
      int pricePerNight = 700,
      int? amount,
      DateTime? paidAt,
    }) async {
      final id = newId();
      await db
          .into(db.refunds)
          .insert(
            RefundsCompanion.insert(
              id: Value(id),
              createdAt: Value(t0),
              updatedAt: Value(t0),
              deviceId: Value(deviceId),
              stayId: stayId ?? st,
              nights: nights,
              pricePerNight: pricePerNight,
              amount: amount ?? nights * pricePerNight,
              requestedBy: u,
              requestedAt: t0,
              paidAt: Value(paidAt),
            ),
          );
      return id;
    }

    Future<int> decide(String refundId, String decision, {String? note}) => db
        .into(db.refundDecisions)
        .insert(
          RefundDecisionsCompanion.insert(
            id: Value(newId()),
            createdAt: Value(t0),
            updatedAt: Value(t0),
            deviceId: Value(deviceId),
            refundId: refundId,
            decision: decision,
            note: Value(note),
            decidedBy: u,
            decidedAt: t0,
          ),
        );

    /// A direct update that moves updated_at, as the writer would.
    Future<int> change(String refundId, RefundsCompanion values) =>
        (db.update(db.refunds)..where((r) => r.id.equals(refundId))).write(
          values.copyWith(updatedAt: Value(t0.add(Duration(seconds: ++tick)))),
        );

    Future<int> payout(
      String refundId, {
      String method = 'cash',
      String? code,
      String receipt = 'R-000101',
    }) => change(
      refundId,
      RefundsCompanion(
        method: Value(method),
        mpesaCode: Value(code),
        shiftId: Value(s),
        paidBy: Value(u),
        paidAt: Value(t0),
        receiptNumber: Value(receipt),
      ),
    );

    Matcher aborts(String message) =>
        throwsA(predicate((e) => '$e'.contains(message), message));

    test('amount must equal nights × price_per_night, nights ≥ 1', () async {
      await expectLater(refund(amount: 1000), _violates('CHECK'));
      await expectLater(refund(nights: 0), _violates('CHECK'));
    });

    test('one refund per stay', () async {
      await refund();
      await expectLater(refund(), _violates('UNIQUE'));
    });

    test('a refund starts as an unpaid request', () async {
      await expectLater(
        refund(paidAt: t0),
        aborts('a refund is requested before it is paid'),
      );
    });

    test('payout is refused until approved, and after a rejection', () async {
      final r = await refund();
      await expectLater(payout(r), aborts('refund is not approved'));
      await decide(r, 'rejected', note: 'Damage');
      await expectLater(payout(r), aborts('refund is not approved'));
    });

    test(
      'an approved refund is paid once; reprints are still counted',
      () async {
        final r = await refund();
        await decide(r, 'approved');
        await payout(r);
        await expectLater(
          payout(r, receipt: 'R-000102'),
          aborts('refund is already paid'),
        );
        await change(r, const RefundsCompanion(printCount: Value(1)));
        final row = await (db.select(
          db.refunds,
        )..where((x) => x.id.equals(r))).getSingle();
        expect((row.receiptNumber, row.printCount), ('R-000101', 1));
      },
    );

    test('nobody can change what was requested', () async {
      final r = await refund();
      await decide(r, 'approved');
      await expectLater(
        change(
          r,
          const RefundsCompanion(nights: Value(4), amount: Value(2800)),
        ),
        aborts('refund terms cannot change'),
      );
      await expectLater(
        change(r, const RefundsCompanion(amount: Value(1))),
        aborts('refund terms cannot change'),
      );
    });

    test(
      'payout fields are set together; paybill needs a code, cash none',
      () async {
        final r = await refund();
        await decide(r, 'approved');
        await expectLater(
          change(r, RefundsCompanion(paidAt: Value(t0))),
          _violates('CHECK'),
        );
        await expectLater(payout(r, method: 'paybill'), _violates('CHECK'));
        await expectLater(payout(r, code: 'SJK4H7XQ2P'), _violates('CHECK'));
        await expectLater(payout(r, method: 'mpesa'), _violates('CHECK'));
        await payout(r, method: 'paybill', code: 'SJK4H7XQ2P');
      },
    );

    test(
      'a decision is one per refund, and a rejection needs a reason',
      () async {
        final r = await refund();
        await expectLater(decide(r, 'rejected'), _violates('CHECK'));
        await expectLater(
          decide(r, 'rejected', note: '  '),
          _violates('CHECK'),
        );
        await expectLater(decide(r, 'maybe'), _violates('CHECK'));
        await decide(r, 'approved');
        await expectLater(
          decide(r, 'rejected', note: 'x'),
          _violates('UNIQUE'),
        );
      },
    );

    test(
      'refunds and decisions are never deleted; decisions never edited',
      () async {
        final r = await refund();
        await decide(r, 'approved');
        await expectLater(
          db.delete(db.refunds).go(),
          aborts('refunds rows are never deleted'),
        );
        await expectLater(
          db.delete(db.refundDecisions).go(),
          aborts('refund_decisions rows are never deleted'),
        );
        await expectLater(
          db
              .update(db.refundDecisions)
              .write(
                RefundDecisionsCompanion(
                  decision: const Value('rejected'),
                  note: const Value('changed my mind'),
                  updatedAt: Value(t0.add(const Duration(hours: 1))),
                ),
              ),
          aborts('refund_decisions rows are never edited'),
        );
      },
    );

    group('an M-Pesa code is used once across payments and refund payouts '
        '(BR-10)', () {
      test('a payment code cannot be reused for a refund payout', () async {
        await payment(
          s,
          u,
          receipt: 'R-000001',
          method: 'paybill',
          mpesaCode: 'SJK4H7XQ2P',
        );
        final r = await refund();
        await decide(r, 'approved');
        await expectLater(
          payout(r, method: 'paybill', code: 'sjk4h7xq2p'),
          aborts('M-Pesa code already used'),
        );
      });

      test('a refund payout code cannot be reused for a payment', () async {
        final r = await refund();
        await decide(r, 'approved');
        await payout(r, method: 'paybill', code: 'SJK4H7XQ2P');
        await expectLater(
          payment(
            s,
            u,
            receipt: 'R-000001',
            method: 'paybill',
            mpesaCode: 'sjk4h7xq2p',
          ),
          aborts('M-Pesa code already used'),
        );
      });
    });

    test('a void can target a refund payout', () async {
      final r = await refund();
      await db
          .into(db.voids)
          .insert(
            VoidsCompanion.insert(
              id: Value(newId()),
              createdAt: Value(t0),
              updatedAt: Value(t0),
              deviceId: Value(deviceId),
              targetType: 'refund',
              targetId: r,
              reason: 'Paid twice by mistake',
              voidedBy: u,
              voidedAt: t0,
            ),
          );
    });
  });

  group('admin records', () {
    test('a void needs a non-blank reason', () async {
      final u = await user();
      Future<int> voidRow(String reason) => db
          .into(db.voids)
          .insert(
            VoidsCompanion.insert(
              id: Value(newId()),
              createdAt: Value(t0),
              updatedAt: Value(t0),
              deviceId: Value(deviceId),
              targetType: 'payment',
              targetId: newId(),
              reason: reason,
              voidedBy: u,
              voidedAt: t0,
            ),
          );
      await expectLater(voidRow('   '), _violates('CHECK'));
      await voidRow('Wrong bed');
    });

    test('expense date must be YYYY-MM-DD', () async {
      final u = await user();
      Future<int> expense(String spentOn) => db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: Value(newId()),
              createdAt: Value(t0),
              updatedAt: Value(t0),
              deviceId: Value(deviceId),
              category: 'laundry',
              amount: 300,
              spentOn: spentOn,
              recordedBy: u,
            ),
          );
      await expense('2026-10-14');
      for (final bad in ['14/10/2026', 'abcd-ef-gh', '2026-1-14x']) {
        await expectLater(expense(bad), _violates('CHECK'), reason: bad);
      }
    });

    test('stock movement quantity must be positive', () async {
      final u = await user();
      final item = newId();
      await db
          .into(db.inventoryItems)
          .insert(
            InventoryItemsCompanion.insert(
              id: Value(item),
              createdAt: Value(t0),
              updatedAt: Value(t0),
              deviceId: Value(deviceId),
              name: 'Soap',
              unit: 'bar',
              lowStockLevel: 5,
            ),
          );
      await expectLater(
        db
            .into(db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                id: Value(newId()),
                createdAt: Value(t0),
                updatedAt: Value(t0),
                deviceId: Value(deviceId),
                itemId: item,
                direction: 'in',
                quantity: 0,
                reason: 'Delivery',
                recordedBy: u,
              ),
            ),
        _violates('CHECK'),
      );
    });
  });
}
