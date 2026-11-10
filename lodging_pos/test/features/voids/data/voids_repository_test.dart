import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/dashboard/data/dashboard_repository.dart';
import 'package:lodging_pos/features/dashboard/domain/dashboard.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/receipts/data/receipts_repository.dart';
import 'package:lodging_pos/features/receipts/domain/receipt.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/stays/data/check_in_repository.dart';
import 'package:lodging_pos/features/stays/data/extend_repository.dart';
import 'package:lodging_pos/features/stays/domain/check_in.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';
import 'package:lodging_pos/features/voids/data/voids_repository.dart';
import 'package:lodging_pos/features/voids/domain/void_rules.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount supervisor;
  late UserAccount desk;
  late VoidsRepository repo;
  late RoomSummary room;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 11, 9, 19)); // Mon 19:00
    supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    desk = await env.addReceptionist('desk');
    repo = VoidsRepository(env.db, env.audit);
    room = await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '4',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe, // 700
        bedBCategoryId: SeedIds.comfort, // 600
      ),
    );
  });
  tearDown(() => env.close());

  Future<String> paymentOf(String stayId) async =>
      (await (env.db.select(env.db.stayCharges)
                ..where((c) => c.stayId.equals(stayId))
                ..orderBy([(c) => OrderingTerm.asc(c.periodStart)]))
              .get())
          .first
          .paymentId;

  Future<StayRow> stayRow(String id) =>
      (env.db.select(env.db.stays)..where((s) => s.id.equals(id))).getSingle();

  Future<BedRow> bedRow(String id) =>
      (env.db.select(env.db.beds)..where((b) => b.id.equals(id))).getSingle();

  Future<List<VoidRow>> voids() => env.db.select(env.db.voids).get();

  group('voiding a payment', () {
    test('a supervisor voids a receptionist\'s payment: one void row, the '
        'stay stays active, the shift no longer counts it', () async {
      final stayId = await env.checkIn(room.beds[0].id, by: desk);
      final paymentId = await paymentOf(stayId);
      final shiftId = (await ShiftRepository(
        env.db,
        env.audit,
      ).openShiftOnThisDevice())!.id;
      expect(
        (await ShiftRepository(env.db, env.audit).takings(shiftId)).received,
        700,
      );

      final view = await repo.view(paymentId);
      expect(view.paymentPlan.staysLeftInUse.single.id, stayId);
      expect(voidBlocker(view.paymentPlan, supervisor), isNull);

      env.clock.set(nairobiInstant(2026, 11, 9, 19, 30));
      await repo.voidPayment(supervisor, paymentId, '  Wrong method  ');

      final v = (await voids()).single;
      expect(
        (v.targetType, v.targetId, v.reason, v.voidedBy),
        ('payment', paymentId, 'Wrong method', supervisor.id),
      );
      expect(v.voidedAt, nairobiInstant(2026, 11, 9, 19, 30));
      expect((await stayRow(stayId)).status, 'active');
      expect(
        (await ShiftRepository(env.db, env.audit).takings(shiftId)).received,
        0,
      );

      final after = await repo.view(paymentId);
      expect(after.paymentVoid?.reason, 'Wrong method');
      expect(after.paymentVoid?.voidedBy, supervisor.fullName);
      expect(
        voidBlocker(after.paymentPlan, owner),
        'R-000001 has already been voided.',
      );
    });

    test('its receipt says VOID, on screen, in the list and in the file '
        'name; reprints too', () async {
      final stayId = await env.checkIn(room.beds[0].id, by: desk);
      final paymentId = await paymentOf(stayId);
      final receipts = ReceiptsRepository(env.db, env.audit);
      expect((await receipts.receipt(paymentId)).isVoid, isFalse);

      env.clock.set(nairobiInstant(2026, 11, 10, 8, 5));
      await repo.voidPayment(supervisor, paymentId, 'Duplicate');

      final r = await receipts.receipt(paymentId);
      expect(
        r.voidLine,
        'Voided Tue 10 Nov 2026, 08:05 by Grace Supervisor: Duplicate',
      );
      expect(r.total, 700);
      expect(receiptFileName(r), 'R-000001 VOID.pdf');
      final listed = await receipts.watchReceipts('').first;
      expect(listed.single.isVoid, isTrue);
      await receipts.markPrinted(desk, paymentId);
      expect(
        receiptFileName(await receipts.receipt(paymentId)),
        'R-000001 VOID COPY 1.pdf',
      );
    });

    test('Today: the guest in a bed with a voided payment, until the stay '
        'is voided too', () async {
      final stayId = await env.checkIn(room.beds[0].id, by: desk);
      final paymentId = await paymentOf(stayId);
      final dashboard = DashboardRepository(env.db);
      expect(unpaidStays(await dashboard.activeStayCharges()), isEmpty);

      await repo.voidPayment(supervisor, paymentId, 'Never paid');
      final row = unpaidStays(await dashboard.activeStayCharges()).single;
      expect(
        (row.stayId, row.subtitle, row.figure),
        (stayId, 'Room 4 · Bed A · R-000001 voided', 'KES 700'),
      );

      await repo.voidStay(owner, stayId, 'Checked in again correctly');
      expect(unpaidStays(await dashboard.activeStayCharges()), isEmpty);
    });

    test('audited as void.create, with an outbox row to push', () async {
      final stayId = await env.checkIn(room.beds[0].id, by: desk);
      final paymentId = await paymentOf(stayId);
      await repo.voidPayment(owner, paymentId, 'Never paid');

      final audit = await env.auditFor('void.create');
      expect(audit.single.entity, 'voids');
      expect(audit.single.userId, owner.id);
      final outbox = await (env.db.select(
        env.db.outbox,
      )..where((o) => o.targetTable.equals('voids'))).get();
      expect(outbox.single.sentAt, isNull);
    });

    test('nobody voids their own payment; the reason is required; a '
        'receptionist may not void', () async {
      final stayId = await env.checkIn(room.beds[0].id, by: supervisor);
      final paymentId = await paymentOf(stayId);

      await expectLater(
        repo.voidPayment(supervisor, paymentId, 'Wrong method'),
        throwsA(
          isA<VoidRuleViolation>().having(
            (e) => e.message,
            'message',
            'You took R-000001 yourself, so someone else must void it.',
          ),
        ),
      );
      await expectLater(
        repo.voidPayment(owner, paymentId, '   '),
        throwsA(isA<VoidRuleViolation>()),
      );
      await expectLater(
        repo.voidPayment(desk, paymentId, 'Wrong method'),
        throwsA(isA<NotPermitted>()),
      );
      expect(await voids(), isEmpty);
      expect(await env.auditFor('void.create'), isEmpty);

      await repo.voidPayment(owner, paymentId, 'Wrong method');
      await expectLater(
        repo.voidPayment(owner, paymentId, 'Again'),
        throwsA(isA<VoidRuleViolation>()),
      );
      expect(await voids(), hasLength(1));
    });

    test('a stay with a refund: neither it nor its payments', () async {
      final stayId = await env.checkIn(room.beds[0].id, by: desk, nights: 3);
      env.clock.set(nairobiInstant(2026, 11, 10, 10, 30));
      await env.checkOut(stayId, by: desk);
      final paymentId = await paymentOf(stayId);

      await expectLater(
        repo.voidPayment(supervisor, paymentId, 'Wrong method'),
        throwsA(isA<VoidRuleViolation>()),
      );
      await expectLater(
        repo.voidStay(supervisor, stayId, 'Wrong guest'),
        throwsA(isA<VoidRuleViolation>()),
      );
      expect(await voids(), isEmpty);
    });
  });

  group('voiding a stay', () {
    test('an active stay: voided with its payments in one operation; the '
        'bed becomes available and needs cleaning', () async {
      final bedId = room.beds[0].id;
      final stayId = await env.checkIn(bedId, by: desk);
      env.clock.set(nairobiInstant(2026, 11, 9, 20));
      final detail = await env.checkOuts.stay(stayId);
      await ExtendRepository(env.db, env.audit).extend(
        desk,
        ExtendRequest(
          stayId: stayId,
          nights: 1,
          shownPaidUntil: detail.stay.paidUntil,
          method: PaymentMethod.cash,
          mpesaCode: null,
        ),
      );
      final payments = await (env.db.select(env.db.payments)).get();
      expect(payments, hasLength(2));

      env.clock.set(nairobiInstant(2026, 11, 9, 21));
      await repo.voidStay(supervisor, stayId, 'Checked into the wrong bed');

      final rows = await voids();
      expect(
        {for (final v in rows) (v.targetType, v.targetId)},
        {('stay', stayId), for (final p in payments) ('payment', p.id)},
      );
      expect({for (final v in rows) v.reason}, {'Checked into the wrong bed'});
      final stay = await stayRow(stayId);
      expect(
        (stay.status, stay.checkedOutAt, stay.checkedOutBy),
        ('closed', nairobiInstant(2026, 11, 9, 21), supervisor.id),
      );
      expect((await bedRow(bedId)).cleanliness, 'not_cleaned');

      final audit = await env.auditFor('void.create');
      expect({for (final a in audit) a.entity}, {'voids', 'stays', 'beds'});
      expect({for (final a in audit) a.operationId}, hasLength(1));

      // Nothing else to void: the stay and its payments are done.
      final view = await repo.view(payments.first.id);
      expect(
        voidBlocker(view.stayPlan, owner),
        'Room 4 · Bed A has already been voided.',
      );
      expect(view.stayVoid?.reason, 'Checked into the wrong bed');
    });

    test('a closed stay: voided; its bed is left as it is', () async {
      final bedId = room.beds[0].id;
      final stayId = await env.checkIn(bedId, by: desk);
      env.clock.set(nairobiInstant(2026, 11, 10, 9));
      await env.checkOut(stayId, by: desk);
      final checkedOut = await stayRow(stayId);
      final bedBefore = await bedRow(bedId);

      await repo.voidStay(owner, stayId, 'Test check-in');

      final stay = await stayRow(stayId);
      expect(stay.checkedOutAt, checkedOut.checkedOutAt);
      expect(stay.checkedOutBy, desk.id);
      expect((await bedRow(bedId)).updatedAt, bedBefore.updatedAt);
      final audit = await env.auditFor('void.create');
      expect({for (final a in audit) a.entity}, {'voids'});
    });

    test('one payment for both beds: both stays and the payment go', () async {
      await env.openShift(desk, startingCash: 0);
      final guests = env.guests;
      final result = await CheckInRepository(env.db, env.audit, guests).checkIn(
        desk,
        CheckInRequest(
          guest: NewGuest(
            const GuestForm(
              fullName: 'Both Beds',
              phone: '0711000482',
              idType: null,
              idNumber: '',
            ),
            phoneSharedWith: const {},
          ),
          method: PaymentMethod.cash,
          mpesaCode: null,
          shown: quoteCheckIn(
            checkInAt: env.clock.now(),
            nights: 1,
            checkout: const ClockTime(10, 0),
            beds: [
              for (final (i, price) in [(0, 700), (1, 600)])
                LetBed(
                  bedId: room.beds[i].id,
                  categoryId: i == 0 ? SeedIds.deluxe : SeedIds.comfort,
                  categoryName: i == 0 ? 'Deluxe' : 'Comfort',
                  pricePerNight: price,
                ),
            ],
          ),
        ),
      );
      expect(result.stayIds, hasLength(2));

      final view = await repo.view(result.paymentId);
      expect(view.stayPlan.stays, hasLength(2));
      expect(view.stayPlan.amount, 1300);

      await repo.voidStay(supervisor, result.stayIds.first, 'Duplicate');
      final rows = await voids();
      expect(rows, hasLength(3));
      for (final id in result.stayIds) {
        expect((await stayRow(id)).status, 'closed');
      }
      for (final b in room.beds) {
        expect((await bedRow(b.id)).cleanliness, 'not_cleaned');
      }
    });
  });

  group('a payment from a closed shift', () {
    test(
      'the closed figures never change; the void shows beside them',
      () async {
        final shifts = ShiftRepository(env.db, env.audit);
        final stayId = await env.checkIn(room.beds[0].id, by: desk);
        final paymentId = await paymentOf(stayId);
        final shift = (await shifts.openShiftOnThisDevice())!;
        env.clock.set(nairobiInstant(2026, 11, 9, 23));
        await env.closeShiftWith(
          desk,
          shift.id,
          firstCount: 500,
          reason: 'The guest paid by M-Pesa, not cash',
        );
        final closed = await (env.db.select(
          env.db.shifts,
        )..where((s) => s.id.equals(shift.id))).getSingle();
        expect((closed.expectedCash, closed.variance), (700, -200));

        env.clock.set(nairobiInstant(2026, 11, 10, 8));
        await repo.voidPayment(supervisor, paymentId, 'Was M-Pesa, not cash');

        final again = await (env.db.select(
          env.db.shifts,
        )..where((s) => s.id.equals(shift.id))).getSingle();
        expect((again.expectedCash, again.variance), (700, -200));
        expect(again.updatedAt, closed.updatedAt);

        final summary = (await shifts.watchShifts().first).single;
        expect(summary.voidedAfterClose.cash, 700);
        expect(summary.voidedAfterClose.paybill, 0);
        expect(summary.voidedAfterClose.varianceAfter(summary.variance!), 500);
      },
    );
  });
}
