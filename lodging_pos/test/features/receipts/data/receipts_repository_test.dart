import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/receipts/data/receipts_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/stays/data/check_in_repository.dart';
import 'package:lodging_pos/features/stays/domain/check_in.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late UserAccount desk;
  late RoomsRepository rooms;
  late ReceiptsRepository receipts;

  setUp(() async {
    env = TestEnv(); // Wed 14 Oct 22:00 Nairobi
    supervisor = await env.users.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('mary');
    rooms = RoomsRepository(env.db, env.audit);
    receipts = ReceiptsRepository(env.db, env.audit);
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 0);
  });
  tearDown(() => env.close());

  Future<RoomSummary> room(String number) => rooms.createRoom(
    supervisor,
    NewRoom(
      number: number,
      floor: null,
      notes: null,
      bedACategoryId: SeedIds.deluxe,
      bedBCategoryId: SeedIds.comfort,
    ),
  );

  Future<Guest> guest(String name, String phone) => env.guests.register(
    desk,
    GuestForm(fullName: name, phone: phone, idType: null, idNumber: ''),
  );

  Future<CheckInResult> checkIn(
    List<BedSummary> beds,
    Guest g, {
    int nights = 2,
    PaymentMethod method = PaymentMethod.paybill,
    String? code = 'QJK7H2LM4P',
  }) => env.checkIns.checkIn(
    desk,
    CheckInRequest(
      guest: ReturningGuest(g.id),
      method: method,
      mpesaCode: method == PaymentMethod.paybill ? code : null,
      shown: quoteCheckIn(
        checkInAt: env.clock.now(),
        nights: nights,
        checkout: const ClockTime(10, 0),
        beds: [
          for (final b in beds)
            LetBed(
              bedId: b.id,
              categoryId: b.categoryId,
              categoryName: b.categoryName,
              pricePerNight: b.pricePerNight,
            ),
        ],
      ),
    ),
  );

  test('a check-in’s receipt, as the artboard prints it', () async {
    final r7 = await room('7');
    final grace = await guest('Grace Achieng', '0722418905');
    final saved = await checkIn([r7.beds.first], grace);

    final r = await receipts.receipt(saved.paymentId);
    expect(r.lodgingName, 'Sunrise Lodge');
    expect(r.receiptNumber, 'R-000001');
    expect(r.issued, 'Wed 14 Oct 2026, 22:00');
    expect(r.guestName, 'Grace Achieng');
    expect(r.roomAndBed, 'Room 7 · Bed A');
    expect(r.category, 'Deluxe');
    expect(r.fromText, 'Wed 14 Oct, 22:00');
    expect(r.checkOutByText, 'Fri 16 Oct, 10:00');
    expect(r.chargeRows, [('2 nights', '2 × 700')]);
    expect(r.totalText, 'KES 1,400');
    expect((r.paidBy, r.mpesaCode), ('M-Pesa', 'QJK7H2LM4P'));
    expect(r.servedBy, 'Desk MARY');
    expect(r.isCopy, isFalse);
    expect(
      r.footer.last,
      'Checkout is at 10:00. After 11:00, one more night is charged.',
    );
  });

  test('both beds: one receipt with a line per bed, A then B', () async {
    final r7 = await room('7');
    final grace = await guest('Grace Achieng', '0722418905');
    final saved = await checkIn(r7.beds, grace, method: PaymentMethod.cash);

    final r = await receipts.receipt(saved.paymentId);
    expect(r.roomAndBed, 'Room 7 · Beds A and B');
    expect(r.chargeRows, [
      ('Bed A · Deluxe', '2 × 700'),
      ('Bed B · Comfort', '2 × 600'),
    ]);
    expect(r.total, 2600);
    expect((r.paidBy, r.mpesaCode), ('Cash', null));
  });

  test('a renumbered room or a renamed price keeps the receipt as let '
      '(v3, v2)', () async {
    final r7 = await room('7');
    final grace = await guest('Grace Achieng', '0722418905');
    final saved = await checkIn([r7.beds.first], grace);
    await rooms.updateRoom(
      supervisor,
      r7.id,
      const RoomEdit(number: '70', floor: null, notes: null),
    );
    final r = await receipts.receipt(saved.paymentId);
    expect(r.roomAndBed, 'Room 7 · Bed A');
  });

  group('printing or saving (payment.print)', () {
    test('the first is the original, later ones COPY; watched', () async {
      final r7 = await room('7');
      final grace = await guest('Grace Achieng', '0722418905');
      final saved = await checkIn([r7.beds.first], grace);

      final seen = <bool>[];
      final sub = receipts
          .watchReceipt(saved.paymentId)
          .listen((r) => seen.add(r.isCopy));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.last, isFalse);

      await receipts.markPrinted(desk, saved.paymentId);
      await pumpEventQueue();
      expect(seen.last, isTrue);
      await receipts.markPrinted(desk, saved.paymentId);
      expect((await receipts.receipt(saved.paymentId)).printCount, 2);

      final audit = await env.auditFor('payment.print');
      expect(audit, hasLength(2));
      expect(audit.first.entity, 'payments');
      expect(audit.first.userId, desk.id);
    });

    test('a disabled user can’t', () async {
      final r7 = await room('7');
      final grace = await guest('Grace Achieng', '0722418905');
      final saved = await checkIn([r7.beds.first], grace);
      final disabled = UserAccount(
        id: desk.id,
        fullName: desk.fullName,
        username: desk.username,
        role: desk.role,
        isActive: false,
        mustChangePassword: false,
      );
      expect(
        () => receipts.markPrinted(disabled, saved.paymentId),
        throwsA(isA<NotPermitted>()),
      );
    });
  });

  group('the list', () {
    late List<CheckInResult> saved;

    setUp(() async {
      final r7 = await room('7');
      final r8 = await room('8');
      final grace = await guest('Grace Achieng', '0722418905');
      final peter = await guest('Peter Kamau', '0711000111');
      saved = [
        await checkIn([r7.beds.first], grace, code: 'AAA1111111'),
        await checkIn(r8.beds, peter, method: PaymentMethod.cash),
      ];
    });

    Future<List<String>> numbers(String text) async => [
      for (final s in await receipts.watchReceipts(text).first) s.receiptNumber,
    ];

    test('newest first, one row per receipt', () async {
      final list = await receipts.watchReceipts('').first;
      expect([for (final s in list) s.receiptNumber], ['R-000002', 'R-000001']);
      expect(list.first.roomAndBed, 'Room 8 · Beds A and B');
      expect(list.first.total, 2600);
      expect(list.first.guestPhone, '0711000111');
      expect(list.first.paymentId, saved.last.paymentId);
    });

    test('search by receipt number or phone, never by name', () async {
      expect(await numbers('R-000001'), ['R-000001']);
      expect(await numbers('r-000002'), ['R-000002']);
      expect(await numbers('2'), ['R-000002']);
      expect(await numbers('0722 41'), ['R-000001']);
      expect(await numbers('+254 711'), ['R-000002']);
      expect(await numbers('Grace'), isEmpty);
      expect(await numbers('nothing'), isEmpty);
    });
  });
}
