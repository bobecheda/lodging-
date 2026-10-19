import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/receipts/data/receipts_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/shifts/domain/shift_rules.dart';
import 'package:lodging_pos/features/stays/data/check_out_repository.dart';
import 'package:lodging_pos/features/stays/data/extend_repository.dart';
import 'package:lodging_pos/features/stays/domain/check_out.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount desk;
  late ExtendRepository repo;
  late String stayId;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19)); // Thu 19:00
    owner = await env.users.createFirstAdmin(testSetup);
    desk = await env.addReceptionist('mary');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 0);
    repo = ExtendRepository(env.db, env.audit);
    final room = await RoomsRepository(env.db, env.audit).createRoom(
      owner,
      const NewRoom(
        number: '5',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe, // 700
        bedBCategoryId: null,
      ),
    );
    // 1 night: paid to Fri 16 Oct, 10:00. Receipt R-000001.
    stayId = await env.checkIn(room.beds.single.id, by: desk);
  });
  tearDown(() => env.close());

  Future<StayDetail> detail() => env.checkOuts.stay(stayId);

  Future<ExtendResult> extend(
    int nights, {
    UserAccount? by,
    PaymentMethod? method = PaymentMethod.cash,
    String? code,
    DateTime? shownPaidUntil,
  }) async => repo.extend(
    by ?? desk,
    ExtendRequest(
      stayId: stayId,
      nights: nights,
      shownPaidUntil: shownPaidUntil ?? (await detail()).stay.paidUntil,
      method: method,
      mpesaCode: code,
    ),
  );

  test('n nights from paid_until: an extension charge, paid_until moved, '
      'its own payment and receipt, audited under one operation', () async {
    env.clock.set(nairobiInstant(2026, 10, 16, 8)); // Fri 08:00
    final result = await extend(2);

    expect(result.newPaidUntil, nairobiInstant(2026, 10, 18, 10));
    final d = await detail();
    expect(d.stay.paidUntil, result.newPaidUntil);
    final charge = d.charges.last;
    expect(charge.charge.kind, ChargeKind.extension);
    expect(charge.charge.periodStart, nairobiInstant(2026, 10, 16, 10));
    expect((charge.charge.pricePerNight, charge.charge.amount), (700, 1400));
    expect(charge.receiptNumber, 'R-000002');

    final payment = await (env.db.select(
      env.db.payments,
    )..where((p) => p.id.equals(result.paymentId))).getSingle();
    expect((payment.amount, payment.method), (1400, 'cash'));

    final extendAudit = await env.auditFor('stay.extend');
    final paymentAudit = await env.auditFor('payment.create');
    expect({for (final a in extendAudit) a.entity}, {'stay_charges', 'stays'});
    expect({
      for (final a in [...extendAudit, paymentAudit.last]) a.operationId,
    }, hasLength(1));

    final receipt = await ReceiptsRepository(
      env.db,
      env.audit,
    ).receipt(result.paymentId);
    expect(receipt.isExtension, isTrue);
    expect(receipt.stayRows.first, ('Charge', 'Extension · 2 nights'));
    expect(receipt.checkOutByText, 'Sun 18 Oct, 10:00');
  });

  test('during an overstay, at least the nights already started; then it '
      'is no longer an overstay', () async {
    env.clock.set(nairobiInstant(2026, 10, 18, 12)); // Sun 12:00: 3 started
    await expectLater(
      extend(2),
      throwsA(
        isA<ExtendRefused>().having(
          (e) => e.message,
          'message',
          'Another night has started, so at least 3 nights are needed now. '
              'Check and extend again.',
        ),
      ),
    );
    final result = await extend(3);
    expect(result.newPaidUntil, nairobiInstant(2026, 10, 19, 10)); // Mon
    expect(
      occupancyAt(
        paidUntil: result.newPaidUntil,
        now: env.clock.now(),
        graceMinutes: 60,
      ),
      Occupancy.occupied,
    );
  });

  test('extended meanwhile: refused, nothing saved', () async {
    final shown = (await detail()).stay.paidUntil;
    await extend(1);
    await expectLater(
      extend(1, shownPaidUntil: shown),
      throwsA(isA<ExtendRefused>()),
    );
    expect((await detail()).charges, hasLength(2));
  });

  test('payment rules: a method, and an unused M-Pesa code', () async {
    await expectLater(
      extend(1, method: null),
      throwsA(
        isA<InvalidLatePayment>().having(
          (e) => e.message,
          'message',
          'Choose how they paid.',
        ),
      ),
    );
    await extend(1, method: PaymentMethod.paybill, code: 'qjk7h2lm4p');
    await expectLater(
      extend(1, method: PaymentMethod.paybill, code: 'QJK7H2LM4P'),
      throwsA(isA<InvalidLatePayment>()),
    );
    expect((await detail()).charges, hasLength(2));
  });

  test('BR-12: your own open shift; a closed stay can’t be extended', () async {
    await expectLater(extend(1, by: owner), throwsA(isA<NoOpenShift>()));
    await env.checkOut(stayId, by: desk);
    await expectLater(
      extend(1),
      throwsA(
        isA<ExtendRefused>().having(
          (e) => e.message,
          'message',
          'This guest has already checked out.',
        ),
      ),
    );
  });

  test('an early checkout after an extension refunds unused nights from '
      'both charges at the locked price', () async {
    env.clock.set(nairobiInstant(2026, 10, 16, 8));
    await extend(3); // paid to Mon 19 Oct, 10:00; 4 nights
    env.clock.set(nairobiInstant(2026, 10, 17, 15)); // Sat 15:00
    final result = await env.checkOut(stayId, by: desk);
    final early = result.terms as EarlyCheckout;
    expect((early.nightsUsed, early.refund.nights), (3, 1));
    final refund = await env.db.select(env.db.refunds).getSingle();
    expect((refund.pricePerNight, refund.amount), (700, 700));
  });
}
