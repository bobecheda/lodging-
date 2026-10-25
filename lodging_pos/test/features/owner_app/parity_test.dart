import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/audit/audit_writer.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/sync/desk_secret_store.dart';
import 'package:lodging_pos/core/sync/sync_engine.dart';
import 'package:lodging_pos/features/bed_board/data/bed_board_repository.dart';
import 'package:lodging_pos/features/bed_board/domain/bed_board.dart';
import 'package:lodging_pos/features/dashboard/data/dashboard_repository.dart';
import 'package:lodging_pos/features/dashboard/domain/dashboard.dart';
import 'package:lodging_pos/features/owner_app/data/owner_today_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../../helpers/fake_cloud.dart';
import '../../helpers/fake_owner_cloud.dart';
import '../../helpers/fixtures.dart';

/// The phone's figures equal the desk's, exactly: the desk records real
/// stays, a refund paid out and voids, pushes them with the real sync
/// engine, and the phone reads the very rows it pushed.
void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount desk;
  late RoomSummary room;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 9, 29, 19)); // Tue 29 Sep
    final supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    desk = await env.addReceptionist('desk');
    final rooms = RoomsRepository(env.db, env.audit);
    room = await rooms.createRoom(
      supervisor,
      const NewRoom(
        number: '5',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe, // 700
        bedBCategoryId: SeedIds.comfort, // 600
      ),
    );
  });
  tearDown(() => env.close());

  Future<void> write(
    String action,
    Future<void> Function(AuditedWrites w) body,
  ) => env.audit.writeWithAudit(action: action, userId: owner.id, body: body);

  Future<void> voidRow(String type, String id) => write(
    'void.create',
    (w) => w.insert(
      env.db.voids,
      VoidsCompanion.insert(
        targetType: type,
        targetId: id,
        reason: 'Entered twice',
        voidedBy: owner.id,
        voidedAt: env.clock.now(),
      ),
    ),
  );

  /// The housekeeper cleans [bedId] (no money, nothing sold).
  Future<void> clean(String bedId) => write(
    'bed.mark_clean',
    (w) => w.update(
      env.db.beds,
      bedId,
      const BedsCompanion(cleanliness: Value('clean')),
    ),
  );

  Future<String> paymentOf(String stayId) async => (await (env.db.select(
    env.db.stayCharges,
  )..where((c) => c.stayId.equals(stayId))).get()).first.paymentId;

  test('Money, Today and Beds: phone and desk agree to the shilling', () async {
    final a = room.beds.first.id; // Deluxe
    final b = room.beds.last.id; // Comfort

    // A: 29 Sep, 4 nights across the month end (29, 30 Sep, 1, 2 Oct).
    await env.checkIn(a, by: desk, nights: 4);
    // B: 15 Oct, 3 nights; leaves on the 16th: 2 nights refunded, approved
    // and paid out at noon.
    env.clock.set(nairobiInstant(2026, 10, 3, 10)); // A's bed comes free
    final stayA = (await env.db.select(env.db.stays).getSingle()).id;
    await env.checkOut(stayA, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 15, 19));
    final stayB = await env.checkIn(b, by: desk, nights: 3);
    env.clock.set(nairobiInstant(2026, 10, 16, 10, 30));
    await env.checkOut(stayB, by: desk);
    final refund = await env.db.select(env.db.refunds).getSingle();
    await write(
      'refund.approve',
      (w) => w.insert(
        env.db.refundDecisions,
        RefundDecisionsCompanion.insert(
          refundId: refund.id,
          decision: 'approved',
          decidedBy: owner.id,
          decidedAt: env.clock.now(),
        ),
      ),
    );
    env.clock.set(nairobiInstant(2026, 10, 16, 12));
    final shift = await ShiftRepository(
      env.db,
      env.audit,
    ).openShiftOnThisDevice();
    await env.audit.writeWithAudit(
      action: 'refund.pay',
      userId: desk.id,
      body: (w) => w.update(
        env.db.refunds,
        refund.id,
        RefundsCompanion(
          method: const Value('cash'),
          shiftId: Value(shift!.id),
          paidBy: Value(desk.id),
          paidAt: Value(env.clock.now()),
          receiptNumber: const Value('R-000099'),
        ),
      ),
    );
    // C: 20 Oct, 2 nights, entered by mistake: the stay and its payment
    // voided.
    env.clock.set(nairobiInstant(2026, 10, 20, 19));
    await clean(b);
    final stayC = await env.checkIn(b, by: desk, nights: 2);
    await voidRow('stay', stayC);
    await voidRow('payment', await paymentOf(stayC));
    // The bed is freed (its refund request moves no money).
    env.clock.set(nairobiInstant(2026, 10, 20, 19, 5));
    await env.checkOut(stayC, by: desk);
    // D: 21 Oct, 1 night, still in the bed on the 23rd: an overstay the
    // desk hasn't charged (the 22nd's night isn't sold).
    env.clock.set(nairobiInstant(2026, 10, 21, 19));
    await clean(a);
    await env.checkIn(a, by: desk, nights: 1);
    final now = nairobiInstant(2026, 10, 23, 9, 30);
    env.clock.set(now);

    // The desk pushes everything (the first upload), as it would.
    final deskCloud = FakeCloud(serverNow: () => env.clock.now());
    final engine = SyncEngine(
      db: env.db,
      audit: env.audit,
      cloud: deskCloud,
      secrets: MemoryDeskSecretStore(),
      clock: env.clock,
    );
    addTearDown(engine.dispose);
    await engine.start();
    await engine.connect(
      owner: owner,
      installCode: 'ABCD-EFGH-JKLM',
      ownerEmail: testOwnerEmail,
      password: testOwner.password,
    );

    // The phone reads what the desk pushed.
    final phoneCloud = FakeOwnerCloud.fromDesk(
      deskCloud,
      serverNow: () => env.clock.now(),
    );
    final phone = await OwnerTodayRepository(phoneCloud).load(now);

    final deskRepo = DashboardRepository(env.db);
    final from = monthStart(sameMomentLastMonth(now));
    final deskMoves = await deskRepo.moneyMoves(from);
    final deskStays = await deskRepo.stayNights(from);

    for (final p in MoneyPeriod.values) {
      final d = periodMoney(deskMoves, p, now);
      final m = periodMoney(phone.moves, p, now);
      expect(
        (m.received, m.refundsPaid, m.voided, m.net, m.before),
        (d.received, d.refundsPaid, d.voided, d.net, d.before),
        reason: '$p',
      );
      expect(
        (m.takings.cash, m.takings.mpesa),
        (d.takings.cash, d.takings.mpesa),
      );
      final dates = periodDates(p, now);
      List<(String, int, int)> rows(Iterable<StayNights> s) => [
        for (final r in nightsLetByCategory(
          s,
          first: dates.first,
          last: dates.last,
        ))
          (r.name, r.nights, r.value),
      ];
      expect(rows(phone.stays), rows(deskStays), reason: '$p');
    }
    List<(DateTime, int)> days(List<DayNet> l) => [
      for (final d in l) (d.day, d.net),
    ];
    expect(days(dailyNet(phone.moves, now)), days(dailyNet(deskMoves, now)));

    // The figures themselves, by hand: October so far is B's 1,800 + D's
    // 700 − the 1,200 refund (C's 2 Comfort nights, 1,200, voided).
    final month = periodMoney(phone.moves, MoneyPeriod.month, now);
    expect(
      (month.received, month.refundsPaid, month.voided, month.net),
      (2500, 1200, 1200, 1300),
    );
    // Nights let in October: A's 1 and 2 Oct, D's 21 Oct (Deluxe); B's 15
    // Oct only (2 refunded); C voided; D's overstay night not charged.
    expect(
      [
        for (final r in nightsLetByCategory(
          phone.stays,
          first: DateTime.utc(2026, 10, 1),
          last: DateTime.utc(2026, 10, 23),
        ))
          (r.name, r.nights, r.value),
      ],
      [('Deluxe', 3, 2100), ('Comfort', 1, 600)],
    );

    final deskMonth = thisMonth(
      moves: deskMoves,
      stays: deskStays,
      activeBeds: 2,
      now: now,
    );
    final phoneMonth = thisMonth(
      moves: phone.moves,
      stays: phone.stays,
      activeBeds: 2,
      now: now,
    );
    expect(
      (phoneMonth.revenue, phoneMonth.occupancy, phoneMonth.occupancyLastMonth),
      (deskMonth.revenue, deskMonth.occupancy, deskMonth.occupancyLastMonth),
    );

    // Beds: the same statuses from the same stays and clock.
    final deskBoard = await BedBoardRepository(env.db).watchBoard().first;
    Map<BoardStatus, int> counts(List<BoardRoom> rooms) => boardView(
      rooms,
      const BoardFilter(),
      now: now,
      graceMinutes: phone.graceMinutes,
    ).counts;
    expect(counts(phone.rooms), counts(deskBoard));
    expect(counts(phone.rooms)[BoardStatus.overstay], 1);
  });
}
