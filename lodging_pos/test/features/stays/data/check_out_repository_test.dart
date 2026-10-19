import 'package:drift/drift.dart' show Table, TableInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/receipts/data/receipts_repository.dart';
import 'package:lodging_pos/features/refunds/domain/refund.dart';
import 'package:lodging_pos/features/setup/data/prices_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/shifts/domain/shift_rules.dart';
import 'package:lodging_pos/features/stays/data/check_out_repository.dart';
import 'package:lodging_pos/features/stays/domain/check_out.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount desk;
  late CheckOutRepository repo;
  late RoomSummary r5;

  setUp(() async {
    env = TestEnv();
    // Thu 15 Oct 19:00 Nairobi.
    env.clock.set(nairobiInstant(2026, 10, 15, 19));
    owner = await env.users.createFirstAdmin(testSetup);
    desk = await env.addReceptionist('mary');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 0);
    repo = env.checkOuts;
    r5 = await RoomsRepository(env.db, env.audit).createRoom(
      owner,
      const NewRoom(
        number: '5',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe, // 700
        bedBCategoryId: null,
      ),
    );
  });
  tearDown(() => env.close());

  Future<int> count<T extends Table, D>(TableInfo<T, D> table) async =>
      (await env.db.select(table).get()).length;

  /// Checks [stayId] out at the current time, as the panel would show it.
  Future<CheckOutResult> checkOutNow(
    String stayId, {
    PaymentMethod? method,
    String? code,
    UserAccount? by,
  }) async {
    final terms = checkoutTerms(
      (await repo.stay(stayId)).stay,
      env.clock.now(),
      60,
    );
    return repo.checkOut(
      by ?? desk,
      CheckOutRequest(
        stayId: stayId,
        shown: terms,
        method: method,
        mpesaCode: code,
      ),
    );
  }

  Future<void> expectClosedAndDirty(String stayId) async {
    final stay = await repo.stay(stayId);
    expect(stay.isActive, isFalse);
    expect(stay.checkedOutAt, env.clock.now());
    final bed = await (env.db.select(
      env.db.beds,
    )..where((b) => b.id.equals(stay.bedId))).getSingle();
    expect(bed.cleanliness, 'not_cleaned');
  }

  test('the panel’s view of a stay: guest, room as let, paid charges with '
      'their receipts', () async {
    final stayId = await env.checkIn(r5.beds.single.id, by: desk, nights: 2);
    final detail = await repo.stay(stayId);
    expect(detail.isActive, isTrue);
    expect((detail.roomNumber, detail.bedLabel), ('5', 'A'));
    expect(detail.guest.fullName, 'Test Guest');
    expect(detail.charges.single.receiptNumber, 'R-000001');
    expect(detail.stay.paidUntil, nairobiInstant(2026, 10, 17, 10));
  });

  test(
    'on time: closed, bed needs cleaning, no money, stay.check_out',
    () async {
      final stayId = await env.checkIn(r5.beds.single.id, by: desk);
      env.clock.set(nairobiInstant(2026, 10, 16, 10, 45)); // within grace
      final result = await checkOutNow(stayId);

      expect(result.terms, isA<OnTimeCheckout>());
      await expectClosedAndDirty(stayId);
      expect(await count(env.db.refunds), 0);
      expect(await count(env.db.payments), 1); // just the check-in
      final audit = await env.auditFor('stay.check_out');
      expect({for (final a in audit) a.entity}, {'stays', 'beds'});
    },
  );

  test('required test case 9: early checkout → a refund request at the '
      'check-in price, even after a price change', () async {
    final stayId = await env.checkIn(r5.beds.single.id, by: desk, nights: 10);
    await PricesRepository(
      env.db,
      env.audit,
    ).savePrices(owner, {SeedIds.deluxe: 750});
    env.clock.set(nairobiInstant(2026, 10, 21, 15)); // Wed 15:00
    final result = await checkOutNow(stayId);

    final early = result.terms as EarlyCheckout;
    expect((early.nightsUsed, early.refund.nights), (7, 3));
    final refund = await env.db.select(env.db.refunds).getSingle();
    expect(refund.stayId, stayId);
    expect(
      (refund.nights, refund.pricePerNight, refund.amount),
      (3, 700, 2100),
    );
    expect(refund.requestedBy, desk.id);
    // A request: no decision, no payout.
    expect(refund.paidAt, isNull);
    expect(await count(env.db.refundDecisions), 0);
    expect(result.guestPhone, '0700000000');
    await expectClosedAndDirty(stayId);

    final request = (await env.auditFor('refund.request')).single;
    final close = (await env.auditFor('stay.check_out')).first;
    expect(request.operationId, close.operationId);
  });

  test('required test case 11: a 1-night stay leaving early requests '
      'nothing', () async {
    final stayId = await env.checkIn(r5.beds.single.id, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 8));
    expect((await checkOutNow(stayId)).terms, isA<OnTimeCheckout>());
    expect(await count(env.db.refunds), 0);
  });

  group('required test case 8: late checkout', () {
    test('one night charged first, with its own payment and receipt; '
        'paid_until moves, then the stay closes', () async {
      final stayId = await env.checkIn(r5.beds.single.id, by: desk);
      env.clock.set(nairobiInstant(2026, 10, 16, 11, 30));
      final result = await checkOutNow(
        stayId,
        method: PaymentMethod.paybill,
        code: 'qjk7h2lm4p',
      );

      expect(result.terms, isA<LateCheckout>());
      final payment = await (env.db.select(
        env.db.payments,
      )..where((p) => p.id.equals(result.paymentId!))).getSingle();
      expect(payment.receiptNumber, 'R-000002');
      expect((payment.amount, payment.method), (700, 'paybill'));
      expect(payment.mpesaCode, 'QJK7H2LM4P');
      final charges = (await repo.stay(stayId)).charges;
      expect(charges.last.charge.kind.code, 'late_checkout');
      expect(charges.last.receiptNumber, 'R-000002');
      final stay = await repo.stay(stayId);
      expect(stay.stay.paidUntil, nairobiInstant(2026, 10, 17, 10));
      await expectClosedAndDirty(stayId);

      expect(await env.auditFor('stay.late_charge'), hasLength(2));
      expect(await env.auditFor('payment.create'), hasLength(2));

      // Its receipt: a late-checkout receipt.
      final receipt = await ReceiptsRepository(
        env.db,
        env.audit,
      ).receipt(result.paymentId!);
      expect(receipt.isLateCheckout, isTrue);
      expect(receipt.stayRows.last, ('Checked out', 'Fri 16 Oct, 11:30'));
    });

    test('two days late at 12:00: 3 nights', () async {
      final stayId = await env.checkIn(r5.beds.single.id, by: desk);
      env.clock.set(nairobiInstant(2026, 10, 18, 12));
      final result = await checkOutNow(stayId, method: PaymentMethod.cash);
      expect((result.terms as LateCheckout).charge.nights, 3);
      final payment = await (env.db.select(
        env.db.payments,
      )..where((p) => p.id.equals(result.paymentId!))).getSingle();
      expect(payment.amount, 2100);
    });

    test('the payment needs a method, and an unused M-Pesa code; nothing is '
        'saved otherwise', () async {
      final stayId = await env.checkIn(r5.beds.single.id, by: desk);
      env.clock.set(nairobiInstant(2026, 10, 16, 11, 30));
      await expectLater(
        checkOutNow(stayId),
        throwsA(
          isA<InvalidLatePayment>().having(
            (e) => e.message,
            'message',
            'Choose how they paid.',
          ),
        ),
      );
      await expectLater(
        checkOutNow(stayId, method: PaymentMethod.paybill),
        throwsA(isA<InvalidLatePayment>()),
      );
      expect((await repo.stay(stayId)).isActive, isTrue);
      expect(await count(env.db.payments), 1);
    });
  });

  test('the panel opened within grace, confirmed after it: refused, '
      'nothing saved', () async {
    final stayId = await env.checkIn(r5.beds.single.id, by: desk);
    env.clock.set(nairobiInstant(2026, 10, 16, 10, 58));
    final shown = checkoutTerms(
      (await repo.stay(stayId)).stay,
      env.clock.now(),
      60,
    );
    env.clock.set(nairobiInstant(2026, 10, 16, 11, 1));
    await expectLater(
      repo.checkOut(desk, CheckOutRequest(stayId: stayId, shown: shown)),
      throwsA(
        isA<CheckOutRefused>().having(
          (e) => e.message,
          'message',
          'It’s now past 11:00, so 1 night is charged. Check and confirm '
              'again.',
        ),
      ),
    );
    expect((await repo.stay(stayId)).isActive, isTrue);
  });

  test('already checked out: refused', () async {
    final stayId = await env.checkIn(r5.beds.single.id, by: desk);
    await checkOutNow(stayId);
    await expectLater(
      checkOutNow(stayId),
      throwsA(
        isA<CheckOutRefused>().having(
          (e) => e.message,
          'message',
          'This guest has already checked out.',
        ),
      ),
    );
  });

  test('BR-12: no shift of your own → refused, even when free', () async {
    final stayId = await env.checkIn(r5.beds.single.id, by: desk);
    await expectLater(
      checkOutNow(stayId, by: owner),
      throwsA(isA<NoOpenShift>()),
    );
    expect((await repo.stay(stayId)).isActive, isTrue);
  });

  test('the refund request is a plain request in the refund lifecycle', () {
    // Status is derived: no decision, no payout → requested.
    final r = Refund(
      id: 'r',
      stayId: 's',
      nights: 3,
      pricePerNight: 700,
      amount: 2100,
      requestedBy: 'u',
      requestedAt: DateTime.utc(2026),
    );
    expect(r.status, RefundStatus.requested);
  });
}
