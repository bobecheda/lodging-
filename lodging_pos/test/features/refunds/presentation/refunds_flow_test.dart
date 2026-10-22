import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/refunds/data/refunds_repository.dart';
import 'package:lodging_pos/features/refunds/domain/refund.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount desk;
  late RefundsRepository refunds;
  late String refundId;

  /// Test Guest checks into Room 5 A for 3 nights (R-000001) and leaves
  /// early on Fri 10:30: 2 nights (KES 1,400) to refund.
  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 15, 19));
    final supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    desk = await env.addReceptionist('desk');
    final room = await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '5',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    final stayId = await env.checkIn(room.beds.single.id, by: desk, nights: 3);
    env.clock.set(nairobiInstant(2026, 10, 16, 10, 30));
    await env.checkOut(stayId, by: desk);
    refunds = RefundsRepository(env.db, env.audit);
    refundId = (await env.db.select(env.db.refunds).getSingle()).id;
    env.clock.set(nairobiInstant(2026, 10, 16, 12));
  });
  tearDown(() => env.close());

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  Future<RefundStatus> status() async => (await refunds.view(refundId)).status;

  /// The desk signed in, continuing the shift the check-in opened.
  Future<void> deskSignsIn(WidgetTester tester) async {
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
  }

  group('the owner decides', () {
    testWidgets('from Today: the refund\'s detail as calculated, then '
        'Approve', (tester) async {
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'today.attention.refund.$refundId');
      expect(locationOf(app), Routes.refundDetail);

      expect(text(tester, 'refund.amount'), 'KES 1,400');
      expect(
        text(tester, 'refund.guest'),
        '0700 ••• 000 · Room 5 · Bed A · '
        'Deluxe',
      );
      expect(text(tester, 'refund.paid.0'), '3 nights × KES 700 · R-000001');
      expect(
        text(tester, 'refund.used'),
        '1 (the night they left counts as used)',
      );
      expect(text(tester, 'refund.notUsed'), '2');
      expect(
        text(tester, 'refund.requestedBy'),
        startsWith(
          'Requested by Desk DESK (receptionist) · Fri 16 Oct, '
          '10:30.',
        ),
      );
      // No field anywhere to change the amount.
      expect(find.byType(TextField), findsNothing);

      await tapKey(tester, 'refund.approve');
      expect(await status(), RefundStatus.approved);
      expect(find.byKey(const ValueKey('refund.decided')), findsOneWidget);
      expect(find.byKey(const ValueKey('refund.approve')), findsNothing);

      await tapKey(tester, 'refund.back');
      expect(locationOf(app), Routes.today);
      expect(find.text('Refund to approve'), findsNothing);
    });

    testWidgets('Reject asks for a reason first; Cancel changes nothing', (
      tester,
    ) async {
      await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'today.attention.refund.$refundId');

      await tapKey(tester, 'refund.reject');
      expect(find.text('Reject this refund?'), findsOneWidget);
      await tapKey(tester, 'refund.reason.cancel');
      expect(await status(), RefundStatus.requested);

      await tapKey(tester, 'refund.reject');
      await tapKey(tester, 'refund.reason.reject'); // no reason yet
      expect(
        find.text('Give a reason for rejecting the refund.'),
        findsOneWidget,
      );
      await enterKey(
        tester,
        'refund.reason',
        'Guest agreed to keep the nights',
      );
      await tapKey(tester, 'refund.reason.reject');
      expect(await status(), RefundStatus.rejected);
      expect(
        find.textContaining('“Guest agreed to keep the nights”'),
        findsOneWidget,
      );
    });
  });

  group('the desk', () {
    testWidgets('sees a waiting refund, then a rejection with the owner\'s '
        'reason', (tester) async {
      final app = await pumpDeskApp(tester, env);
      await deskSignsIn(tester);
      await tapKey(tester, 'nav.${Routes.refunds}');
      expect(locationOf(app), Routes.refunds);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('refunds.waiting')),
          matching: find.text('WAITING FOR OWNER APPROVAL'),
        ),
        findsOneWidget,
      );
      expect(find.text('0700 ••• 000 · Room 5 · Bed A · 2 nights'), findsOne);
      expect(find.byKey(ValueKey('refunds.pay.$refundId')), findsNothing);
    });

    testWidgets('a rejection shows the owner\'s reason', (tester) async {
      await refunds.decide(
        owner,
        refundId,
        approve: false,
        note: 'Guest stays on',
      );
      await pumpDeskApp(tester, env);
      await deskSignsIn(tester);
      await tapKey(tester, 'nav.${Routes.refunds}');
      expect(text(tester, 'refunds.reason.$refundId'), '“Guest stays on”');
    });

    testWidgets('pays an approved refund in cash: the method is required; '
        'then the REFUND receipt with Print', (tester) async {
      await refunds.decide(owner, refundId, approve: true);
      await pumpDeskApp(tester, env);
      await deskSignsIn(tester);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('nav.badge.${Routes.refunds}')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'nav.${Routes.refunds}');
      await tapKey(tester, 'refunds.pay.$refundId');
      expect(text(tester, 'pay.amount'), 'KES 1,400');

      await tapKey(tester, 'pay.save'); // no method yet
      expect(text(tester, 'pay.methodError'), 'Choose how it was paid.');

      await tapKeyIn(tester, 'pay.method', 'choice.PaymentMethod.cash');
      await tapKey(tester, 'pay.save');
      expect(await status(), RefundStatus.paid);
      expect(text(tester, 'receipt.title'), 'REFUND');
      expect(text(tester, 'receipt.number'), 'R-000002');
      expect(text(tester, 'receipt.total'), '− KES 1,400');
      expect(find.text('2 nights refunded'), findsOneWidget);
      await tapKey(tester, 'receipt.print');
      expect(env.receiptOutput.printed, ['R-000002.pdf']);

      await tapKey(tester, 'pay.done');
      expect(find.text('Nothing to pay.'), findsOneWidget);
    });

    testWidgets('pays by M-Pesa: the guest\'s phone filled in, editable; the '
        'code required; the receipt says where it went, masked', (
      tester,
    ) async {
      await refunds.decide(owner, refundId, approve: true);
      await pumpDeskApp(tester, env);
      await deskSignsIn(tester);
      await tapKey(tester, 'nav.${Routes.refunds}');
      await tapKey(tester, 'refunds.pay.$refundId');
      await tapKeyIn(tester, 'pay.method', 'choice.PaymentMethod.paybill');
      final sendTo = tester.widget<TextField>(
        find.byKey(const ValueKey('pay.sendTo')),
      );
      expect(sendTo.controller!.text, '0700000000');

      await enterKey(tester, 'pay.sendTo', '0711 000 482');
      await tapKey(tester, 'pay.save'); // no code
      expect(find.text('Enter the M-Pesa code.'), findsOneWidget);
      await enterKey(tester, 'pay.mpesaCode', 'qjk7h2lm4p');
      await tapKey(tester, 'pay.save');

      expect(await status(), RefundStatus.paid);
      final row = await env.db.select(env.db.refunds).getSingle();
      expect((row.payoutPhone, row.mpesaCode), ('0711000482', 'QJK7H2LM4P'));
      expect(find.text('0711 ••• 482'), findsOneWidget);
      expect(find.text('QJK7H2LM4P'), findsOneWidget);
    });

    testWidgets('a supervisor with no shift of their own: the note, and Pay '
        'is off', (tester) async {
      await refunds.decide(owner, refundId, approve: true);
      await pumpDeskApp(tester, env);
      await signInAs(tester, 'supervisor', 'super-pass');
      await tapKey(tester, 'nav.${Routes.refunds}');
      await tapKey(tester, 'refunds.pay.$refundId');
      expect(find.byKey(const ValueKey('pay.noShift')), findsOneWidget);
      final pay = tester.widget<TextButton>(
        find.descendant(
          of: find.byKey(const ValueKey('pay.save')),
          matching: find.byType(TextButton),
        ),
      );
      expect(pay.onPressed, isNull);
      expect(await status(), RefundStatus.approved);
    });
  });

  testWidgets('Receipts lists the REFUND receipt', (tester) async {
    await refunds.decide(owner, refundId, approve: true);
    await refunds.pay(
      desk,
      PayoutRequest(refundId: refundId, method: PaymentMethod.cash),
    );
    final app = await pumpDeskApp(tester, env);
    await deskSignsIn(tester);
    await tapKey(tester, 'nav.${Routes.receipts}');
    expect(locationOf(app), Routes.receipts);
    expect(find.text('R-000002'), findsWidgets);
  });
}
