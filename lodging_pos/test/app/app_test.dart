import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import '../helpers/fixtures.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  testWidgets('first run: setup creates the owner, then goes to sign in', (
    tester,
  ) async {
    final app = await pumpDeskApp(tester, env);
    expect(find.text('Set up this lodging'), findsOneWidget);

    await enterKey(tester, 'setup.lodgingName', 'Sunrise Lodge');
    await enterKey(tester, 'setup.fullName', 'Grace Owner');
    await enterKey(tester, 'setup.username', 'Owner');
    await enterKey(tester, 'setup.password', 'owner-pass');
    await enterKey(tester, 'setup.confirmPassword', 'owner-pass');
    await tapKey(tester, 'setup.submit');

    expect(locationOf(app), Routes.login);
    expect(
      (await env.users.findByUsername('owner'))?.account.fullName,
      'Grace Owner',
    );
    // The brand panel now shows the lodging name.
    expect(find.text('Sunrise Lodge'), findsOneWidget);
  });

  testWidgets('setup shows field errors and saves nothing', (tester) async {
    await pumpDeskApp(tester, env);
    await tapKey(tester, 'setup.submit');
    expect(find.text('Enter the lodging name'), findsOneWidget);
    expect(await env.users.hasAnyUser(), isFalse);
  });

  testWidgets('once any user exists, the setup screen is unreachable', (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    final app = await pumpDeskApp(tester, env);
    expect(locationOf(app), Routes.login);

    // Signed out: navigating to setup lands on sign in.
    app.read(routerProvider).go(Routes.setup);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.login);
    expect(find.text('Set up this lodging'), findsNothing);

    // Signed in: it lands on home instead.
    await signInAs(tester, 'owner', 'owner-pass');
    app.read(routerProvider).go(Routes.setup);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.home);
    expect(find.text('Set up this lodging'), findsNothing);
  });

  testWidgets('the owner signs in straight to home without a shift', (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'OWNER', 'owner-pass');
    expect(locationOf(app), Routes.home);
    expect(find.text('Grace Owner'), findsOneWidget);
    expect(find.text('Owner · admin'), findsOneWidget);
    expect(find.text('Bed board'), findsWidgets);
    expect(await env.db.select(env.db.shifts).get(), isEmpty);
  });

  testWidgets('a wrong password stays on sign in with a message', (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'wrong-pass');
    expect(locationOf(app), Routes.login);
    expect(find.text('Wrong username or password. Try again.'), findsOneWidget);
  });

  testWidgets('must change password, then open a shift, then home (FD-1)', (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    await env.addReceptionist('desk', mustChangePassword: true);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    expect(locationOf(app), Routes.changePassword);

    // Nothing else is reachable until the password is changed.
    for (final route in [Routes.home, Routes.shift, Routes.login]) {
      app.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      expect(locationOf(app), Routes.changePassword, reason: route);
    }

    await enterKey(tester, 'password.new', 'my-own-pass');
    await enterKey(tester, 'password.confirm', 'my-own-pass');
    await tapKey(tester, 'password.submit');
    expect(locationOf(app), Routes.shift);
    expect(find.text('Good evening, Desk'), findsOneWidget);

    // No check-in or payment screen is reachable without an open shift.
    app.read(routerProvider).go(Routes.home);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.shift);

    await enterKey(tester, 'shift.float', '1500');
    // The money input groups thousands as you type.
    expect(find.text('1,500'), findsOneWidget);
    await tapKey(tester, 'shift.submit');
    expect(locationOf(app), Routes.home);
    expect((await env.db.select(env.db.shifts).getSingle()).openingFloat, 1500);
    expect(find.text('Receptionist · shift since 22:00'), findsOneWidget);
    expect(await env.auditFor('shift.open'), hasLength(1));
  });

  testWidgets('an empty float is rejected on screen', (tester) async {
    await env.users.createFirstAdmin(testSetup);
    await env.addReceptionist('desk');
    await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.submit');
    expect(find.text('Enter the opening cash float'), findsOneWidget);
    expect(await env.auditFor('shift.open'), isEmpty);
  });

  testWidgets("another receptionist is blocked by an open shift", (
    tester,
  ) async {
    await env.users.createFirstAdmin(testSetup);
    final desk = await env.addReceptionist('desk');
    await env.addReceptionist('tom');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 1000);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'tom', 'desk-pass');
    expect(locationOf(app), Routes.shift);
    expect(find.text("Desk's shift must be closed first"), findsOneWidget);
    expect(
      find.textContaining('Desk DESK has had a shift open'),
      findsOneWidget,
    );
  });

  testWidgets(
    'the shift owner sees the resume card with takings, then continues',
    (tester) async {
      final owner = await env.users.createFirstAdmin(testSetup);
      final desk = await env.addReceptionist('desk');
      await ShiftRepository(
        env.db,
        env.audit,
      ).openShift(user: desk, openingFloat: 800);
      // Two payments on the shift, one voided, to show takings.
      await _twoPaymentsOneVoided(env, desk.id, owner.id);

      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'desk', 'desk-pass');
      expect(locationOf(app), Routes.shift);
      expect(find.text('Welcome back, Desk'), findsOneWidget);
      final total = tester.widget<Text>(
        find.byKey(const ValueKey('shift.takenTotal')),
      );
      expect(total.data, 'KES 700'); // the voided 1,000 is not counted
      expect(find.text('KES 800'), findsOneWidget); // opening float

      await tapKey(tester, 'shift.continue');
      expect(locationOf(app), Routes.home);
      expect(find.text('Bed board'), findsWidgets);
      expect(find.text('Receptionist · shift since 22:00'), findsOneWidget);
    },
  );

  testWidgets('the resume card shows a paid refund as received, refunded and '
      'net', (tester) async {
    final owner = await env.users.createFirstAdmin(testSetup);
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 800);
    final room = await RoomsRepository(env.db, env.audit).createRoom(
      owner,
      const NewRoom(
        number: '3',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    // 3 nights paid in cash (2,100), then 2 nights refunded in cash (1,400).
    final stayId = await env.checkIn(room.beds.single.id, by: desk, nights: 3);
    await _paidCashRefund(env, stayId, deskId: desk.id, ownerId: owner.id);

    await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    String textOf(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    expect(textOf('shift.takenTotal'), 'KES 700');
    expect(textOf('shift.net.cash'), 'KES 700');
    expect(textOf('shift.net.paybill'), 'KES 0');
    expect(find.text('KES 2,100'), findsOneWidget); // cash received
    expect(find.text('KES -1,400'), findsOneWidget); // cash refunded
    expect(find.text('M-Pesa'), findsOneWidget);
  });
}

/// A refund of 2 nights at 700 for [stayId]: requested by the desk, approved
/// by the owner and paid out in cash in the desk's open shift.
Future<void> _paidCashRefund(
  TestEnv env,
  String stayId, {
  required String deskId,
  required String ownerId,
}) async {
  final shift = await env.db.select(env.db.shifts).getSingle();
  final refund = await env.audit.writeWithAudit(
    action: 'refund.request',
    userId: deskId,
    body: (w) => w.insert(
      env.db.refunds,
      RefundsCompanion.insert(
        stayId: stayId,
        nights: 2,
        pricePerNight: 700,
        amount: 1400,
        requestedBy: deskId,
        requestedAt: w.now,
      ),
    ),
  );
  await env.audit.writeWithAudit(
    action: 'refund.approve',
    userId: ownerId,
    body: (w) => w.insert(
      env.db.refundDecisions,
      RefundDecisionsCompanion.insert(
        refundId: refund.id,
        decision: 'approved',
        decidedBy: ownerId,
        decidedAt: w.now,
      ),
    ),
  );
  await env.audit.writeWithAudit(
    action: 'refund.pay',
    userId: deskId,
    body: (w) => w.update(
      env.db.refunds,
      refund.id,
      RefundsCompanion(
        method: const Value('cash'),
        shiftId: Value(shift.id),
        paidBy: Value(deskId),
        paidAt: Value(w.now),
        receiptNumber: const Value('R-000002'),
      ),
    ),
  );
}

/// A cash payment of 700 and a Paybill payment of 1,000 that is voided.
Future<void> _twoPaymentsOneVoided(
  TestEnv env,
  String deskId,
  String ownerId,
) async {
  final shift = await env.db.select(env.db.shifts).getSingle();
  await env.audit.writeWithAudit(
    action: 'payment.create',
    userId: deskId,
    body: (w) async {
      await w.insert(
        env.db.payments,
        PaymentsCompanion.insert(
          receiptNumber: 'R-000001',
          shiftId: shift.id,
          receivedBy: deskId,
          receivedAt: env.clock.now(),
          amount: 700,
          method: 'cash',
        ),
      );
      final paybill = await w.insert(
        env.db.payments,
        PaymentsCompanion.insert(
          receiptNumber: 'R-000002',
          shiftId: shift.id,
          receivedBy: deskId,
          receivedAt: env.clock.now(),
          amount: 1000,
          method: 'paybill',
          mpesaCode: const Value('SJK4H7XQ2P'),
        ),
      );
      await w.insert(
        env.db.voids,
        VoidsCompanion.insert(
          targetType: 'payment',
          targetId: paybill.id,
          reason: 'Wrong amount',
          voidedBy: ownerId,
          voidedAt: env.clock.now(),
        ),
        action: 'void.create',
      );
    },
  );
}
