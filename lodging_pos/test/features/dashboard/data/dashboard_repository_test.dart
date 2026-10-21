import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/dashboard/data/dashboard_repository.dart';
import 'package:lodging_pos/features/dashboard/domain/dashboard.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount desk;
  late DashboardRepository repo;
  late RoomSummary room;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19)); // Thu 19:00
    final supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    desk = await env.addReceptionist('desk');
    repo = DashboardRepository(env.db);
    room = await RoomsRepository(env.db, env.audit).createRoom(
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

  /// An early checkout of a 3-night stay on Fri 10:30: night 1 used, 2
  /// refunded (KES 1,400). Returns the stay id.
  Future<String> leaveEarly() async {
    final stayId = await env.checkIn(room.beds.first.id, by: desk, nights: 3);
    env.clock.set(nairobiInstant(2026, 10, 16, 10, 30));
    await env.checkOut(stayId, by: desk);
    return stayId;
  }

  Future<RefundRow> refund() => env.db.select(env.db.refunds).getSingle();

  Future<void> decide(String decision) async {
    final r = await refund();
    await env.audit.writeWithAudit(
      action: 'refund.${decision == 'approved' ? 'approve' : 'reject'}',
      userId: owner.id,
      body: (w) => w.insert(
        env.db.refundDecisions,
        RefundDecisionsCompanion.insert(
          refundId: r.id,
          decision: decision,
          note: Value(decision == 'rejected' ? 'Guest stays on' : null),
          decidedBy: owner.id,
          decidedAt: env.clock.now(),
        ),
      ),
    );
  }

  test('a refund awaiting approval, with guest, bed, nights, amount and who '
      'asked; gone once decided', () async {
    await leaveEarly();
    final awaiting = await repo.refundsAwaiting();
    expect(awaiting, hasLength(1));
    final a = awaiting.single;
    expect(
      (a.guestName, a.roomNumber, a.bedLabel, a.nights, a.amount),
      ('Test Guest', '5', 'A', 2, 1400),
    );
    expect(a.requestedBy, desk.fullName);
    expect(a.requestedAt, nairobiInstant(2026, 10, 16, 10, 30));

    await decide('approved');
    expect(await repo.refundsAwaiting(), isEmpty);
  });

  test('money: payments, a paid refund on its payout day, and voids '
      'marked', () async {
    await leaveEarly();
    await decide('approved');
    final r = await refund();
    final shiftId = (await env.db.select(env.db.shifts).getSingle()).id;
    env.clock.set(nairobiInstant(2026, 10, 16, 12));
    await env.audit.writeWithAudit(
      action: 'refund.pay',
      userId: desk.id,
      body: (w) => w.update(
        env.db.refunds,
        r.id,
        RefundsCompanion(
          method: const Value('cash'),
          shiftId: Value(shiftId),
          paidBy: Value(desk.id),
          paidAt: Value(env.clock.now()),
          receiptNumber: const Value('R-000099'),
        ),
      ),
    );
    final payment = await env.db.select(env.db.payments).getSingle();
    await env.audit.writeWithAudit(
      action: 'void.create',
      userId: owner.id,
      body: (w) => w.insert(
        env.db.voids,
        VoidsCompanion.insert(
          targetType: 'payment',
          targetId: payment.id,
          reason: 'Entered twice',
          voidedBy: owner.id,
          voidedAt: env.clock.now(),
        ),
      ),
    );

    final moves = await repo.moneyMoves(nairobiInstant(2026, 10, 1));
    final pay = moves.singleWhere((m) => !m.isPayout);
    final out = moves.singleWhere((m) => m.isPayout);
    expect((pay.amount, pay.voided), (2100, true));
    expect(
      (out.amount, out.method, out.at, out.voided),
      (1400, PaymentMethod.cash, nairobiInstant(2026, 10, 16, 12), false),
    );
    expect(
      takingsBetween(
        moves,
        from: nairobiInstant(2026, 10, 16),
        to: nairobiInstant(2026, 10, 17),
      ).net,
      -1400,
    );
    // Only from the date asked for.
    expect(await repo.moneyMoves(nairobiInstant(2026, 10, 17)), isEmpty);
  });

  test('nights: each stay with its charges and refunded nights; a rejected '
      'refund gives none back; a voided stay is marked', () async {
    final early = await leaveEarly();
    env.clock.set(nairobiInstant(2026, 10, 16, 19));
    final other = await env.checkIn(room.beds.last.id, by: desk, nights: 2);

    var stays = await repo.stayNights(nairobiInstant(2026, 10, 1));
    expect(stays, hasLength(2));
    final sold = bedNightsSold(
      stays,
      first: DateTime.utc(2026, 10, 1),
      last: DateTime.utc(2026, 10, 31),
    );
    expect(sold, 1 + 2); // early: 1 of 3 kept; other: 2

    await decide('rejected');
    await env.audit.writeWithAudit(
      action: 'void.create',
      userId: owner.id,
      body: (w) => w.insert(
        env.db.voids,
        VoidsCompanion.insert(
          targetType: 'stay',
          targetId: other,
          reason: 'Wrong guest',
          voidedBy: owner.id,
          voidedAt: env.clock.now(),
        ),
      ),
    );
    stays = await repo.stayNights(nairobiInstant(2026, 10, 1));
    expect(
      bedNightsSold(
        stays,
        first: DateTime.utc(2026, 10, 1),
        last: DateTime.utc(2026, 10, 31),
      ),
      3, // early: all 3 (refund rejected); other: voided
    );
    expect(early, isNotEmpty);
  });
}
