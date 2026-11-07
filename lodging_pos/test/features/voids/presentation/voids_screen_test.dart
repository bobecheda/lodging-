import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
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
  late CheckInResult twoBeds;
  late CheckInResult own;

  setUp(() async {
    env = TestEnv(); // Wed 14 Oct 22:00 Nairobi
    supervisor = await env.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('desk');
    final shifts = ShiftRepository(env.db, env.audit);
    await shifts.openShift(user: desk, openingFloat: 0);
    final rooms = RoomsRepository(env.db, env.audit);
    final r8 = await rooms.createRoom(
      supervisor,
      const NewRoom(
        number: '8',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: SeedIds.comfort,
      ),
    );
    final r9 = await rooms.createRoom(
      supervisor,
      const NewRoom(
        number: '9',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    final peter = await env.guests.register(
      desk,
      const GuestForm(
        fullName: 'Peter Kamau',
        phone: '0711000111',
        idType: null,
        idNumber: '',
      ),
    );
    CheckInRequest request(List<BedSummary> beds) => CheckInRequest(
      guest: ReturningGuest(peter.id),
      method: PaymentMethod.cash,
      mpesaCode: null,
      shown: quoteCheckIn(
        checkInAt: env.clock.now(),
        nights: 1,
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
    );
    twoBeds = await env.checkIns.checkIn(desk, request(r8.beds));
    // The supervisor's own payment, in a shift of their own.
    await shifts.closeShift(
      desk,
      (await shifts.openShiftOnThisDevice())!.id,
      firstCount: 1300,
      counted: 1300,
      note: '',
      shown: await shifts.takings((await shifts.openShiftOnThisDevice())!.id),
    );
    await shifts.openShift(user: supervisor, openingFloat: 0);
    own = await env.checkIns.checkIn(supervisor, request(r9.beds));
  });
  tearDown(() => env.close());

  Future<ProviderContainer> openVoids(
    WidgetTester tester, {
    String user = 'Supervisor',
    String password = 'super-pass',
  }) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, user, password);
    await tapKey(tester, 'nav.${Routes.voids}');
    expect(locationOf(app), Routes.voids);
    return app;
  }

  testWidgets('the supervisor voids a two-bed stay: it says what goes, needs '
      'a reason, then the receipt and the list say VOID', (tester) async {
    await openVoids(tester);
    await tapKey(tester, 'voids.item.${twoBeds.receiptNumber}');
    expect(find.byKey(const ValueKey('receipt.void')), findsNothing);

    await tapKey(tester, 'voids.stay');
    expect(
      find.text(
        'Voids Room 8 · Bed A and Room 8 · Bed B, and '
        '${twoBeds.receiptNumber} (KES 1,300). Both beds become available '
        'and need cleaning.',
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'voids.confirm.ok');
    expect(find.text('Say why it is being voided.'), findsOneWidget);
    expect(env.db.select(env.db.voids).get(), completion(isEmpty));

    await enterKey(tester, 'voids.reason', 'Duplicate check-in');
    await tapKey(tester, 'voids.confirm.ok');
    expect(find.byKey(const ValueKey('voids.confirm')), findsNothing);
    expect(find.byKey(const ValueKey('voids.stayVoided')), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt.void')), findsOneWidget);
    expect(find.textContaining('Duplicate check-in'), findsWidgets);
    expect(find.byKey(const ValueKey('voids.stay.blocked')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('their own payment: no button, the reason why', (tester) async {
    await openVoids(tester);
    await tapKey(tester, 'voids.item.${own.receiptNumber}');
    expect(find.byKey(const ValueKey('voids.payment')), findsNothing);
    expect(
      find.text(
        'You took ${own.receiptNumber} yourself, so someone else must void '
        'it.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('voids.stay.blocked')), findsOneWidget);
  });

  testWidgets('the owner has Voids in the sidebar; a receptionist does not', (
    tester,
  ) async {
    await openVoids(tester, user: 'Owner', password: testOwner.password);
    await tapKey(tester, 'voids.item.${own.receiptNumber}');
    expect(find.byKey(const ValueKey('voids.payment')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a receptionist has no Voids', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    expect(find.byKey(const ValueKey('nav.${Routes.voids}')), findsNothing);
    expect(Routes.allows(Routes.voids, desk), isFalse);
    expect(locationOf(app), isNot(Routes.voids));
  });
}
