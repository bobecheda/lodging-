import 'package:drift/drift.dart' show Table, TableInfo, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/auth/permissions.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/guests/data/guests_repository.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/setup/data/prices_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/shifts/domain/shift_rules.dart';
import 'package:lodging_pos/features/stays/data/check_in_repository.dart';
import 'package:lodging_pos/features/stays/domain/check_in.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount supervisor;
  late UserAccount desk;
  late RoomsRepository rooms;
  late ShiftRepository shifts;
  late CheckInRepository repo;
  late GuestsRepository guests;

  setUp(() async {
    env = TestEnv(); // Wed 14 Oct 22:00 Nairobi
    supervisor = await env.users.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('mary');
    rooms = RoomsRepository(env.db, env.audit);
    shifts = ShiftRepository(env.db, env.audit);
    guests = env.guests;
    repo = env.checkIns;
  });
  tearDown(() => env.close());

  /// Room [number]: Bed A Deluxe (700), Bed B Comfort (600) if [twoBeds].
  Future<RoomSummary> room(String number, {bool twoBeds = true}) =>
      rooms.createRoom(
        supervisor,
        NewRoom(
          number: number,
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: twoBeds ? SeedIds.comfort : null,
        ),
      );

  Future<Guest> grace() => guests.register(
    desk,
    const GuestForm(
      fullName: 'Grace Achieng',
      phone: '0722 418 905',
      idType: IdType.nationalId,
      idNumber: '12343921',
    ),
  );

  LetBed let(BedSummary b) => LetBed(
    bedId: b.id,
    categoryId: b.categoryId,
    categoryName: b.categoryName,
    pricePerNight: b.pricePerNight,
  );

  /// What the screen would show for [beds] at [shownAt] (default now).
  CheckInQuote shown(
    List<BedSummary> beds, {
    int nights = 1,
    DateTime? shownAt,
  }) => quoteCheckIn(
    checkInAt: shownAt ?? env.clock.now(),
    nights: nights,
    checkout: const ClockTime(10, 0),
    beds: [for (final b in beds) let(b)],
  );

  Future<CheckInResult> checkIn(
    List<BedSummary> beds, {
    required GuestChoice guest,
    UserAccount? by,
    int nights = 1,
    PaymentMethod method = PaymentMethod.cash,
    String? code,
    DateTime? shownAt,
  }) => repo.checkIn(
    by ?? desk,
    CheckInRequest(
      guest: guest,
      method: method,
      mpesaCode: code,
      shown: shown(beds, nights: nights, shownAt: shownAt),
    ),
  );

  Future<void> openDeskShift() =>
      shifts.openShift(user: desk, openingFloat: 1000);

  Future<int> count<T extends Table, D>(TableInfo<T, D> table) async =>
      (await env.db.select(table).get()).length;

  Future<int> nextReceipt() async =>
      (await env.db.select(env.db.receiptCounter).getSingle()).nextNumber;

  group('one bed, returning guest, cash', () {
    test(
      'saves the stay, its charge and the payment, with receipt R-000001',
      () async {
        await openDeskShift();
        final r7 = await room('7');
        final guest = await grace();

        final result = await checkIn(
          [r7.beds.first],
          guest: ReturningGuest(guest.id),
          nights: 2,
        );

        expect(result.receiptNumber, 'R-000001');
        expect(await nextReceipt(), 2);
        expect(result.roomNumber, '7');
        expect(result.labels, [BedLabel.a]);
        // Wed 22:00 + 2 nights → Fri 10:00.
        expect(result.paidUntil, nairobiInstant(2026, 10, 16, 10));
        expect(result.total, 1400);

        final stay = await env.db.select(env.db.stays).getSingle();
        expect(stay.status, 'active');
        expect(stay.guestId, guest.id);
        expect(stay.checkedInBy, desk.id);
        expect(stay.checkInAt, env.clock.now());
        expect(stay.paidUntil, result.paidUntil);

        final payment = await env.db.select(env.db.payments).getSingle();
        expect(payment.amount, 1400);
        expect(payment.method, 'cash');
        expect(payment.mpesaCode, isNull);
        expect(payment.receivedBy, desk.id);
        expect(payment.shiftId, (await shifts.openShiftOnThisDevice())!.id);

        final charge = await env.db.select(env.db.stayCharges).getSingle();
        expect(charge.stayId, stay.id);
        expect(charge.paymentId, payment.id);
        expect((charge.kind, charge.nights), ('check_in', 2));
        expect((charge.pricePerNight, charge.amount), (700, 1400));
        expect(
          (charge.categoryId, charge.categoryName),
          (SeedIds.deluxe, 'Deluxe'),
        );
        expect(charge.periodEnd, stay.paidUntil);
      },
    );

    test('audit: stay.check_in for the stay and charge, payment.create for '
        'the payment, under one operation', () async {
      await openDeskShift();
      final r7 = await room('7');
      final guest = await grace();
      await checkIn([r7.beds.first], guest: ReturningGuest(guest.id));

      final checkIns = await env.auditFor('stay.check_in');
      final payments = await env.auditFor('payment.create');
      expect({for (final a in checkIns) a.entity}, {'stays', 'stay_charges'});
      expect(payments.single.entity, 'payments');
      expect({
        for (final a in [...checkIns, ...payments]) a.operationId,
      }, hasLength(1));
      for (final a in [...checkIns, ...payments]) {
        expect(a.userId, desk.id);
      }
    });

    test('the price is the category price at that moment and never changes '
        'later (BR-3)', () async {
      await openDeskShift();
      final r7 = await room('7');
      final guest = await grace();
      await checkIn([r7.beds.first], guest: ReturningGuest(guest.id));
      await PricesRepository(
        env.db,
        env.audit,
      ).savePrices(supervisor, {SeedIds.deluxe: 750});
      final charge = await env.db.select(env.db.stayCharges).getSingle();
      expect((charge.pricePerNight, charge.categoryName), (700, 'Deluxe'));
    });

    test('receipt numbers follow on, with the settings prefix', () async {
      await openDeskShift();
      final r7 = await room('7');
      final r8 = await room('8');
      final guest = await grace();
      await checkIn([r7.beds.first], guest: ReturningGuest(guest.id));
      final second = await checkIn([
        r8.beds.first,
      ], guest: ReturningGuest(guest.id));
      expect(second.receiptNumber, 'R-000002');
      expect(await nextReceipt(), 3);
    });
  });

  test('required test case 14: both beds of a room for one guest → two '
      'stays, one payment, one receipt', () async {
    await openDeskShift();
    final r7 = await room('7');
    final guest = await grace();
    final result = await checkIn(
      r7.beds,
      guest: ReturningGuest(guest.id),
      nights: 3,
    );
    expect(result.labels, [BedLabel.a, BedLabel.b]);
    expect(result.stayIds, hasLength(2));
    expect(result.total, 3 * 700 + 3 * 600);

    final stays = await env.db.select(env.db.stays).get();
    expect({for (final s in stays) s.guestId}, {guest.id});
    final payment = await env.db.select(env.db.payments).getSingle();
    expect(payment.amount, 3900);
    final charges = await env.db.select(env.db.stayCharges).get();
    expect({for (final c in charges) c.paymentId}, {payment.id});
    expect({for (final c in charges) c.categoryName}, {'Deluxe', 'Comfort'});
    expect(await nextReceipt(), 2);
  });

  test('beds from two rooms are refused', () async {
    await openDeskShift();
    final r7 = await room('7', twoBeds: false);
    final r8 = await room('8', twoBeds: false);
    final guest = await grace();
    await expectLater(
      checkIn([
        r7.beds.single,
        r8.beds.single,
      ], guest: ReturningGuest(guest.id)),
      throwsA(
        isA<CheckInRefused>().having(
          (e) => e.message,
          'message',
          'Both beds must be in the same room. Choose again.',
        ),
      ),
    );
    expect(await count(env.db.stays), 0);
  });

  group('required test case 15: only Available and Clean beds', () {
    test('a bed that needs cleaning is refused, nothing saved', () async {
      await openDeskShift();
      final r7 = await room('7', twoBeds: false);
      final stay = await env.checkIn(r7.beds.single.id, by: desk);
      await env.checkOut(stay, by: desk); // now not_cleaned
      final guest = await grace();
      final before = await nextReceipt();

      await expectLater(
        checkIn([r7.beds.single], guest: ReturningGuest(guest.id)),
        throwsA(
          isA<CheckInRefused>().having(
            (e) => e.message,
            'message',
            'Room 7 · Bed A needs cleaning first. Choose another bed.',
          ),
        ),
      );
      expect(await count(env.db.stays), 1);
      expect(await nextReceipt(), before);
    });

    test(
      'a bed with a guest is refused (and the database would too)',
      () async {
        await openDeskShift();
        final r7 = await room('7', twoBeds: false);
        await env.checkIn(r7.beds.single.id, by: desk);
        final guest = await grace();
        await expectLater(
          checkIn([r7.beds.single], guest: ReturningGuest(guest.id)),
          throwsA(
            isA<CheckInRefused>().having(
              (e) => e.message,
              'message',
              contains('Bed A has a guest'),
            ),
          ),
        );
      },
    );

    test('a closed bed, or a bed in a closed room, is refused', () async {
      await openDeskShift();
      final r7 = await room('7');
      final r8 = await room('8', twoBeds: false);
      await rooms.deactivateBed(supervisor, r7.beds.last.id);
      await rooms.deactivateRoom(supervisor, r8.id);
      final guest = await grace();
      for (final bed in [r7.beds.last, r8.beds.single]) {
        await expectLater(
          checkIn([bed], guest: ReturningGuest(guest.id)),
          throwsA(
            isA<CheckInRefused>().having(
              (e) => e.message,
              'message',
              contains('is closed'),
            ),
          ),
        );
      }
    });
  });

  group('required test case 17 / BR-12: an open shift of your own', () {
    test('no open shift → refused', () async {
      final r7 = await room('7');
      final guest = await grace();
      await expectLater(
        checkIn(
          [r7.beds.first],
          guest: ReturningGuest(guest.id),
          by: supervisor,
        ),
        throwsA(isA<NoOpenShift>()),
      );
      expect(await count(env.db.payments), 0);
    });

    test('a supervisor can’t take money into a receptionist’s shift', () async {
      await openDeskShift();
      final r7 = await room('7');
      final guest = await grace();
      await expectLater(
        checkIn(
          [r7.beds.first],
          guest: ReturningGuest(guest.id),
          by: supervisor,
        ),
        throwsA(isA<NoOpenShift>()),
      );
    });
  });

  group('required test case 16 / FD-5: M-Pesa', () {
    test(
      'a code is stored in capitals; Paybill without one is refused',
      () async {
        await openDeskShift();
        final r7 = await room('7');
        final guest = await grace();
        await expectLater(
          checkIn(
            [r7.beds.first],
            guest: ReturningGuest(guest.id),
            method: PaymentMethod.paybill,
          ),
          throwsA(
            isA<InvalidCheckIn>().having((e) => e.errors, 'errors', {
              CheckInField.mpesaCode: 'Enter the M-Pesa code.',
            }),
          ),
        );
        await checkIn(
          [r7.beds.first],
          guest: ReturningGuest(guest.id),
          method: PaymentMethod.paybill,
          code: ' qjk7h2lm4p ',
        );
        final payment = await env.db.select(env.db.payments).getSingle();
        expect((payment.method, payment.mpesaCode), ('paybill', 'QJK7H2LM4P'));
      },
    );

    test('a used code is refused, saying where it was used', () async {
      await openDeskShift();
      final r7 = await room('7');
      final guest = await grace();
      await checkIn(
        [r7.beds.first],
        guest: ReturningGuest(guest.id),
        method: PaymentMethod.paybill,
        code: 'QJK7H2LM4P',
      );
      await expectLater(
        checkIn(
          [r7.beds.last],
          guest: ReturningGuest(guest.id),
          method: PaymentMethod.paybill,
          code: 'qjk7h2lm4p',
        ),
        throwsA(
          isA<InvalidCheckIn>().having((e) => e.errors, 'errors', {
            CheckInField.mpesaCode:
                'QJK7H2LM4P was already used on receipt R-000001 (Wed 14 '
                'Oct, 22:00).',
          }),
        ),
      );
      expect(await count(env.db.stays), 1);
    });
  });

  group('a new guest is registered inside the check-in', () {
    const ann = GuestForm(
      fullName: '  Ann   Wambui ',
      phone: '0711 000 111',
      idType: IdType.passport,
      idNumber: 'ak 123456',
    );

    test('guest.create under the same operation, normalized', () async {
      await openDeskShift();
      final r7 = await room('7');
      await checkIn([r7.beds.first], guest: const NewGuest(ann));

      final guest = await env.db.select(env.db.guests).getSingle();
      expect(guest.fullName, 'Ann Wambui');
      expect(guest.phone, '0711000111');
      expect((guest.idType, guest.idNumber), ('passport', 'AK123456'));
      final stay = await env.db.select(env.db.stays).getSingle();
      expect(stay.guestId, guest.id);

      final create = (await env.auditFor('guest.create')).single;
      final stayAudit = (await env.auditFor('stay.check_in')).first;
      expect(create.operationId, stayAudit.operationId);
    });

    test('if the check-in fails, the new guest isn’t saved either', () async {
      await openDeskShift();
      final r7 = await room('7');
      final guest = await grace();
      await checkIn(
        [r7.beds.first],
        guest: ReturningGuest(guest.id),
        method: PaymentMethod.paybill,
        code: 'QJK7H2LM4P',
      );
      await expectLater(
        checkIn(
          [r7.beds.last],
          guest: const NewGuest(ann),
          method: PaymentMethod.paybill,
          code: 'QJK7H2LM4P',
        ),
        throwsA(isA<InvalidCheckIn>()),
      );
      expect(await count(env.db.guests), 1); // just Grace
      expect(await env.auditFor('guest.create'), hasLength(1));
    });

    test('the ID check runs again inside the transaction', () async {
      await openDeskShift();
      final r7 = await room('7');
      // Registered with Ann's passport after the form was filled in.
      await guests.register(
        supervisor,
        const GuestForm(
          fullName: 'Someone Else',
          phone: '0733000000',
          idType: IdType.passport,
          idNumber: 'AK123456',
        ),
      );
      await expectLater(
        checkIn([r7.beds.first], guest: const NewGuest(ann)),
        throwsA(
          isA<InvalidGuest>().having(
            (e) => e.errors[GuestField.idNumber],
            'ID error',
            'This ID is already registered to another guest.',
          ),
        ),
      );
      expect(await count(env.db.stays), 0);
    });

    test('a phone registered since the form showed its notice stops the '
        'save; seen, it may be shared', () async {
      await openDeskShift();
      final r7 = await room('7');
      final family = await guests.register(
        supervisor,
        const GuestForm(
          fullName: 'Peter Wambui',
          phone: '0711000111',
          idType: null,
          idNumber: '',
        ),
      );
      await expectLater(
        checkIn([r7.beds.first], guest: const NewGuest(ann)),
        throwsA(
          isA<PhoneNowShared>()
              .having((e) => e.guests.single.id, 'guest', family.id)
              .having(
                (e) => e.toString(),
                'message',
                'Since you started, Peter Wambui was registered with this '
                    'phone. Choose them, or save again to register a new '
                    'guest.',
              ),
        ),
      );
      await checkIn([
        r7.beds.first,
      ], guest: NewGuest(ann, phoneSharedWith: {family.id}));
      expect(await count(env.db.guests), 2);
    });

    test('registering needs registerGuests', () async {
      // Everyone has it today; the check is still there for new roles.
      expect(can(desk, Permission.registerGuests), isTrue);
    });
  });

  group('what the screen showed is what gets saved', () {
    test('a price change while the screen was open is refused', () async {
      await openDeskShift();
      final r7 = await room('7');
      final guest = await grace();
      final request = CheckInRequest(
        guest: ReturningGuest(guest.id),
        method: PaymentMethod.cash,
        mpesaCode: null,
        shown: shown([r7.beds.first]),
      );
      await PricesRepository(
        env.db,
        env.audit,
      ).savePrices(supervisor, {SeedIds.deluxe: 750});
      await expectLater(
        repo.checkIn(desk, request),
        throwsA(
          isA<CheckInRefused>().having(
            (e) => e.message,
            'message',
            'Deluxe is now KES 750 a night. Check the total and save again.',
          ),
        ),
      );
      expect(await count(env.db.stays), 0);
    });

    test('opened at 23:58, saved at 00:01: checkout moved, refused', () async {
      // Fri 16 Oct 23:58 Nairobi: 1 night → Sat 17 Oct, 10:00 on screen.
      env.clock.set(nairobiInstant(2026, 10, 16, 23, 58));
      await openDeskShift();
      final r7 = await room('7');
      final guest = await grace();
      final opened = env.clock.now();
      env.clock.set(nairobiInstant(2026, 10, 17, 0, 1)); // Sat 00:01

      await expectLater(
        checkIn(
          [r7.beds.first],
          guest: ReturningGuest(guest.id),
          shownAt: opened,
        ),
        throwsA(
          isA<CheckInRefused>().having(
            (e) => e.message,
            'message',
            'It’s now past midnight, so checkout is Sun 18 Oct, 10:00. Check '
                'and save again.',
          ),
        ),
      );
      expect(await count(env.db.stays), 0);
      // Shown again at 00:01, it saves with the new date.
      final result = await checkIn([
        r7.beds.first,
      ], guest: ReturningGuest(guest.id));
      expect(result.paidUntil, nairobiInstant(2026, 10, 18, 10));
    });
  });

  group('reads for the screen', () {
    test('watchRooms lists open rooms with every bed, closed and let ones '
        'too', () async {
      await openDeskShift();
      final r7 = await room('7');
      final r8 = await room('8', twoBeds: false);
      final r9 = await room('9', twoBeds: false);
      await rooms.deactivateBed(supervisor, r7.beds.last.id);
      await rooms.deactivateRoom(supervisor, r9.id);
      await env.checkIn(r8.beds.single.id, by: desk);

      final list = await repo.watchRooms().first;
      expect([for (final r in list) r.number], ['7', '8']);
      final seven = list.first;
      expect(
        [for (final b in seven.beds) (b.label, b.isActive)],
        [(BedLabel.a, true), (BedLabel.b, false)],
      );
      expect(list.last.beds.single.hasActiveStay, isTrue);
      expect(seven.beds.first.hasActiveStay, isFalse);
    });

    test(
      'guestHistory counts check-ins (both beds once) and the last date',
      () async {
        await openDeskShift();
        final r7 = await room('7');
        final r8 = await room('8', twoBeds: false);
        final guest = await grace();
        expect((await repo.guestHistory(guest.id)).stays, 0);

        await checkIn(r7.beds, guest: ReturningGuest(guest.id));
        env.clock.advance(const Duration(days: 2));
        await checkIn([r8.beds.single], guest: ReturningGuest(guest.id));
        final history = await repo.guestHistory(guest.id);
        expect(history.stays, 2);
        expect(history.lastCheckIn, env.clock.now());
      },
    );

    test('watchCheckoutTime follows the setting', () async {
      expect(await repo.watchCheckoutTime().first, const ClockTime(10, 0));
      await env.audit.writeWithAudit(
        action: 'settings.update',
        userId: supervisor.id,
        body: (w) => w.update(
          env.db.settings,
          'checkout_time',
          const SettingsCompanion(value: Value('11:00')),
        ),
      );
      expect(await repo.watchCheckoutTime().first, const ClockTime(11, 0));
    });
  });
}
