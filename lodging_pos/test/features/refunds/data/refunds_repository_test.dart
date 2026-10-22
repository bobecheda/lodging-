import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/receipts/data/receipts_repository.dart';
import 'package:lodging_pos/features/receipts/domain/receipt.dart';
import 'package:lodging_pos/features/refunds/data/refunds_repository.dart';
import 'package:lodging_pos/features/refunds/domain/refund.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/shifts/domain/shift_rules.dart';
import 'package:lodging_pos/features/stays/data/check_out_repository.dart';
import 'package:lodging_pos/features/stays/data/extend_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount supervisor;
  late UserAccount desk;
  late RefundsRepository repo;
  late RoomSummary room;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19)); // Thu 19:00
    supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    desk = await env.addReceptionist('desk');
    repo = RefundsRepository(env.db, env.audit);
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

  /// Checks a guest into [bed] for 3 nights and checks them out early on
  /// Fri 10:30: 2 nights back. Returns the refund id.
  Future<String> requested({int bed = 0}) async {
    env.clock.set(nairobiInstant(2026, 10, 15, 19));
    final stayId = await env.checkIn(room.beds[bed].id, by: desk, nights: 3);
    env.clock.set(nairobiInstant(2026, 10, 16, 10, 30));
    await env.checkOut(stayId, by: desk);
    return (await (env.db.select(
      env.db.refunds,
    )..where((r) => r.stayId.equals(stayId))).getSingle()).id;
  }

  Future<RefundStatus> status(String id) async => (await repo.view(id)).status;

  Future<String> payCash(String id, {UserAccount? by}) => repo.pay(
    by ?? desk,
    PayoutRequest(refundId: id, method: PaymentMethod.cash),
  );

  Map<String, Object?> json(String text) =>
      jsonDecode(text) as Map<String, Object?>;

  group('required test case 12: the lifecycle with real data', () {
    test('requested → approved by the owner → paid once from the desk; the '
        'amount never changes', () async {
      final id = await requested();
      expect(await status(id), RefundStatus.requested);
      expect((await repo.deskRefunds(env.clock.now())).waiting, hasLength(1));

      for (final user in [desk, supervisor]) {
        await expectLater(
          repo.decide(user, id, approve: true),
          throwsA(isA<NotPermitted>()),
        );
      }
      await expectLater(payCash(id), throwsA(isA<RefundRuleViolation>()));

      await repo.decide(owner, id, approve: true);
      expect(await status(id), RefundStatus.approved);
      await expectLater(
        repo.decide(owner, id, approve: false, note: 'Changed my mind'),
        throwsA(
          isA<RefundRuleViolation>().having(
            (e) => e.message,
            'message',
            'This refund has already been decided.',
          ),
        ),
      );
      final desks = await repo.deskRefunds(env.clock.now());
      expect(desks.toPay.single.id, id);
      expect(desks.waiting, isEmpty);

      final number = await payCash(id);
      expect(number, 'R-000002'); // the check-in took R-000001
      final v = await repo.view(id);
      expect(
        (v.status, v.receiptNumber, v.refund.amount),
        (RefundStatus.paid, 'R-000002', 1400),
      );
      expect(v.paidByName, desk.fullName);
      expect(v.decidedByName, owner.fullName);
      await expectLater(payCash(id), throwsA(isA<RefundRuleViolation>()));
      expect((await repo.deskRefunds(env.clock.now())).toPay, isEmpty);

      final approve = (await env.auditFor('refund.approve')).single;
      final pay = (await env.auditFor('refund.pay')).single;
      expect((approve.userId, pay.userId), (owner.id, desk.id));
    });

    test(
      'a rejection needs a reason, which the desk sees for 14 days',
      () async {
        final id = await requested();
        await expectLater(
          repo.decide(owner, id, approve: false, note: '  '),
          throwsA(isA<RefundRuleViolation>()),
        );
        await repo.decide(owner, id, approve: false, note: 'Guest stays on');
        final rejected = (await repo.deskRefunds(env.clock.now())).rejected;
        expect(rejected.single.refund.decision!.note, 'Guest stays on');
        expect(await status(id), RefundStatus.rejected);
        await expectLater(payCash(id), throwsA(isA<RefundRuleViolation>()));

        final later = addNairobiDays(env.clock.now(), 15);
        expect((await repo.deskRefunds(later)).rejected, isEmpty);
      },
    );

    test("the owner's detail: the stay, its receipts and the nights", () async {
      final id = await requested();
      final d = await repo.detail(id);
      expect(d.view.guestName, 'Test Guest');
      expect(
        (d.view.roomNumber, d.view.bedLabel, d.categoryName),
        ('5', 'A', 'Deluxe'),
      );
      expect(d.checkInAt, nairobiInstant(2026, 10, 15, 19));
      expect(d.checkedOutAt, nairobiInstant(2026, 10, 16, 10, 30));
      expect(
        [
          for (final c in d.charges)
            (c.nights, c.pricePerNight, c.receiptNumber),
        ],
        [(3, 700, 'R-000001')],
      );
      expect((d.nightsPaid, d.nightsUsed, d.nightsNotUsed), (3, 1, 2));
      expect(d.view.requestedByRole, Role.receptionist);
    });
  });

  group('required test case 13: money', () {
    test('a cash payout reduces the paying shift\'s expected cash, an M-Pesa '
        'one its M-Pesa total; approved-but-unpaid changes nothing', () async {
      final a = await requested();
      final b = await requested(bed: 1);
      await repo.decide(owner, a, approve: true);
      await repo.decide(owner, b, approve: true);
      final shifts = ShiftRepository(env.db, env.audit);
      final shift = (await shifts.openShiftOnThisDevice())!;
      final before = await shifts.takings(shift.id);
      // 3 × 700 + 3 × 600 received, nothing refunded yet.
      expect((before.cash.received, before.refunded), (3900, 0));

      await payCash(a);
      await repo.pay(
        desk,
        PayoutRequest(
          refundId: b,
          method: PaymentMethod.paybill,
          mpesaCode: 'qjk7h2lm4p',
          sendTo: '0711 000 482',
        ),
      );
      final after = await shifts.takings(shift.id);
      expect(after.cash.refunded, 1400);
      expect(after.paybill.refunded, 1200);
      expect(after.expectedCash(openingFloat: 0), 3900 - 1400);
      expect(after.expectedPaybill, -1200);
    });
  });

  group('required test case 16: M-Pesa codes', () {
    test("a code used on a payment can't be used for a payout, and the other "
        'way round, with the same message as payments', () async {
      final id = await requested();
      await repo.decide(owner, id, approve: true);
      // A guest in bed B extends, paying with a code.
      env.clock.set(nairobiInstant(2026, 10, 16, 11));
      final stayB = await env.checkIn(room.beds[1].id, by: desk);
      final extend = ExtendRepository(env.db, env.audit);
      final b = await env.checkOuts.stay(stayB);
      await extend.extend(
        desk,
        ExtendRequest(
          stayId: stayB,
          nights: 1,
          shownPaidUntil: b.stay.paidUntil,
          method: PaymentMethod.paybill,
          mpesaCode: 'SJK4H7XQ2P',
        ),
      );
      await expectLater(
        repo.pay(
          desk,
          PayoutRequest(
            refundId: id,
            method: PaymentMethod.paybill,
            mpesaCode: 'sjk4h7xq2p',
            sendTo: '0711000482',
          ),
        ),
        throwsA(
          isA<InvalidMpesaCode>().having(
            (e) => e.message,
            'message',
            startsWith('SJK4H7XQ2P was already used on receipt R-'),
          ),
        ),
      );

      await repo.pay(
        desk,
        PayoutRequest(
          refundId: id,
          method: PaymentMethod.paybill,
          mpesaCode: 'QJK7H2LM4P',
          sendTo: '0711000482',
        ),
      );
      final again = await env.checkOuts.stay(stayB);
      await expectLater(
        extend.extend(
          desk,
          ExtendRequest(
            stayId: stayB,
            nights: 1,
            shownPaidUntil: again.stay.paidUntil,
            method: PaymentMethod.paybill,
            mpesaCode: 'QJK7H2LM4P',
          ),
        ),
        throwsA(
          isA<InvalidLatePayment>().having(
            (e) => e.message,
            'message',
            contains('refund receipt'),
          ),
        ),
      );
    });
  });

  test('required test case 17: no shift of your own, no payout', () async {
    final id = await requested();
    await repo.decide(owner, id, approve: true);
    // The supervisor has no shift (the desk's is open on this device).
    await expectLater(payCash(id, by: supervisor), throwsA(isA<NoOpenShift>()));
    await expectLater(payCash(id, by: owner), throwsA(isA<NotPermitted>()));
    expect(await status(id), RefundStatus.approved);
  });

  test('an M-Pesa payout keeps the phone it went to, normalised; the audit '
      'keeps it masked; a bad one is refused', () async {
    final id = await requested();
    await repo.decide(owner, id, approve: true);
    await expectLater(
      repo.pay(
        desk,
        PayoutRequest(
          refundId: id,
          method: PaymentMethod.paybill,
          mpesaCode: 'QJK7H2LM4P',
          sendTo: '0722',
        ),
      ),
      throwsA(isA<InvalidPayoutPhone>()),
    );
    await expectLater(
      repo.pay(desk, PayoutRequest(refundId: id, method: null)),
      throwsA(isA<PayoutRefused>()),
    );
    await repo.pay(
      desk,
      PayoutRequest(
        refundId: id,
        method: PaymentMethod.paybill,
        mpesaCode: 'QJK7H2LM4P',
        sendTo: '+254 711 000 482',
      ),
    );
    final row = await env.db.select(env.db.refunds).getSingle();
    expect((row.payoutPhone, row.mpesaCode), ('0711000482', 'QJK7H2LM4P'));
    final audit = (await env.auditFor('refund.pay')).single;
    expect(json(audit.afterJson)['payout_phone'], '0711•••482');
  });

  test('the REFUND receipt: from the payout, listed and searchable in '
      'Receipts, reprinted as COPY (refund.print)', () async {
    final id = await requested();
    await repo.decide(owner, id, approve: true);
    final number = await repo.pay(
      desk,
      PayoutRequest(
        refundId: id,
        method: PaymentMethod.paybill,
        mpesaCode: 'QJK7H2LM4P',
        sendTo: '0711000482',
      ),
    );
    final receipts = ReceiptsRepository(env.db, env.audit);
    final key = refundReceiptKey(id);
    final r = await receipts.receipt(key);
    expect((r.title, r.receiptNumber, r.total), ('REFUND', number, -1400));
    expect(r.refund!.originalReceipts, ['R-000001']);
    expect((r.refund!.approvedBy, r.servedBy), (owner.fullName, desk.fullName));
    expect(r.refund!.sentTo, '0711000482');
    expect(r.chargeRows, [('2 nights refunded', '2 × 700')]);
    expect(r.isCopy, isFalse);

    final listed = await receipts.watchReceipts('').first;
    final row = listed.firstWhere((s) => s.paymentId == key);
    expect((row.isRefund, row.total, row.receiptNumber), (true, -1400, number));
    expect(
      [for (final s in await receipts.watchReceipts(number).first) s.paymentId],
      [key],
    );
    expect([
      for (final s in await receipts.watchReceipts('0700').first) s.paymentId,
    ], contains(key));

    await receipts.markPrinted(desk, key);
    expect((await receipts.receipt(key)).isCopy, isTrue);
    expect((await env.auditFor('refund.print')).single.userId, desk.id);
  });
}
