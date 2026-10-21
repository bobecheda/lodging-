import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/app/theme/receipt_print_style.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/receipts/data/receipts_repository.dart';
import 'package:lodging_pos/features/receipts/presentation/receipt_pdf.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/stays/data/check_in_repository.dart';
import 'package:lodging_pos/features/stays/domain/check_in.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount desk;
  late List<CheckInResult> saved;

  setUp(() async {
    env = TestEnv(); // Wed 14 Oct 22:00 Nairobi
    final supervisor = await env.users.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 0);
    final rooms = RoomsRepository(env.db, env.audit);
    Future<RoomSummary> room(String n) => rooms.createRoom(
      supervisor,
      NewRoom(
        number: n,
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: SeedIds.comfort,
      ),
    );
    final r7 = await room('7');
    final r8 = await room('8');
    Future<Guest> guest(String name, String phone) => env.guests.register(
      desk,
      GuestForm(fullName: name, phone: phone, idType: null, idNumber: ''),
    );
    final grace = await guest('Grace Achieng', '0722418905');
    final peter = await guest('Peter Kamau', '0711000111');
    Future<CheckInResult> checkIn(
      List<BedSummary> beds,
      Guest g,
      PaymentMethod method,
    ) => env.checkIns.checkIn(
      desk,
      CheckInRequest(
        guest: ReturningGuest(g.id),
        method: method,
        mpesaCode: method == PaymentMethod.paybill ? 'QJK7H2LM4P' : null,
        shown: quoteCheckIn(
          checkInAt: env.clock.now(),
          nights: 2,
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
    saved = [
      await checkIn([r7.beds.first], grace, PaymentMethod.paybill),
      await checkIn(r8.beds, peter, PaymentMethod.cash),
    ];
  });
  tearDown(() => env.close());

  Future<ProviderContainer> openReceipts(WidgetTester tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    await tapKey(tester, 'nav.${Routes.receipts}');
    expect(locationOf(app), Routes.receipts);
    return app;
  }

  List<String> listed(WidgetTester tester) => [
    for (final n in ['R-000001', 'R-000002'])
      if (find.byKey(ValueKey('receipts.item.$n')).evaluate().isNotEmpty) n,
  ];

  testWidgets('lists receipts newest first, phones masked; search by number '
      'or phone, not name', (tester) async {
    await openReceipts(tester);
    expect(listed(tester), ['R-000001', 'R-000002']);
    expect(find.textContaining('0711 ••• 111'), findsOneWidget);
    expect(find.textContaining('0711000111'), findsNothing);

    Future<List<String>> search(String text) async {
      await enterKey(tester, 'receipts.search', text);
      await tester.pumpAndSettle();
      return listed(tester);
    }

    expect(await search('R-000002'), ['R-000002']);
    expect(await search('0722 418'), ['R-000001']);
    expect(await search('Grace'), isEmpty);
    expect(find.byKey(const ValueKey('receipts.none')), findsOneWidget);
  });

  testWidgets('print: the first is the original, the next says COPY; a '
      'cancelled dialog counts nothing', (tester) async {
    await openReceipts(tester);
    await tapKey(tester, 'receipts.item.R-000001');
    expect(find.byKey(const ValueKey('receipt.view')), findsOneWidget);
    expect(find.text('Room 7 · Bed A'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt.copy')), findsNothing);

    env.receiptOutput.printResult = false; // cancelled
    await tapKey(tester, 'receipt.print');
    expect(env.receiptOutput.printed, isEmpty);
    expect(find.byKey(const ValueKey('receipt.copy')), findsNothing);
    expect(await env.auditFor('payment.print'), isEmpty);

    env.receiptOutput.printResult = true;
    await tapKey(tester, 'receipt.print');
    expect(env.receiptOutput.printed, ['R-000001.pdf']);
    expect(find.byKey(const ValueKey('receipt.copy')), findsOneWidget);

    await tapKey(tester, 'receipt.print');
    expect(env.receiptOutput.printed.last, 'R-000001 COPY 1.pdf');
    expect(await env.auditFor('payment.print'), hasLength(2));
    expect(
      utf8.decode(
        env.receiptOutput.lastPdf!.sublist(0, 5),
        allowMalformed: true,
      ),
      '%PDF-',
    );
  });

  testWidgets('Save PDF writes to Documents/<lodging> receipts, counts as '
      'the original, and Open folder shows it', (tester) async {
    await openReceipts(tester);
    await tapKey(tester, 'receipts.item.R-000002');
    await tapKey(tester, 'receipt.save');
    const path = r'C:\Users\Desk\Documents\Sunrise Lodge receipts\R-000002.pdf';
    expect(env.receiptOutput.saved, [path]);
    expect(find.text(path), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt.copy')), findsOneWidget);

    await tapKey(tester, 'receipt.openFolder');
    expect(env.receiptOutput.opened, [path]);
  });

  testWidgets('step 4 after check-in shows the receipt with Print as the '
      'main button, and no dialog opens by itself', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    final rooms = await RoomsRepository(env.db, env.audit).rooms();
    final r7b = rooms.firstWhere((r) => r.number == '7').beds.last;
    app.read(routerProvider).go(Routes.checkInFor(r7b.id));
    await tester.pumpAndSettle();
    await enterKey(tester, 'guests.search', '0722');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grace Achieng').first);
    await tester.pumpAndSettle();
    await tapKey(tester, 'choice.PaymentMethod.cash');
    await tapKey(tester, 'checkIn.save');

    expect(find.byKey(const ValueKey('receipt.view')), findsOneWidget);
    expect(find.text('R-000003'), findsOneWidget);
    expect(env.receiptOutput.printed, isEmpty);
    await tapKey(tester, 'receipt.print');
    expect(env.receiptOutput.printed, ['R-000003.pdf']);
  });

  group('the PDF', () {
    testWidgets('builds on the 80 mm roll, original and copy, one and two '
        'beds', (tester) async {
      final fonts = await tester.runAsync(() => ReceiptFonts.load(rootBundle));
      final repo = ReceiptsRepository(env.db, env.audit);
      for (final s in saved) {
        await repo.markPrinted(desk, s.paymentId); // second build is a COPY
        for (var i = 0; i < 2; i++) {
          final r = await repo.receipt(s.paymentId);
          final pdf = await tester.runAsync(() => buildReceiptPdf(r, fonts!));
          final text = latin1.decode(pdf!);
          expect(text, startsWith('%PDF-'));
          // The page is the roll's width: 80 mm = 226.77 pt.
          expect(text, contains('226.77'));
          await repo.markPrinted(desk, s.paymentId);
        }
      }
      expect(receiptPageFormat.width, closeTo(226.77, 0.01));
    });

    testWidgets('the header is the wordmark: both brand fonts are embedded', (
      tester,
    ) async {
      final fonts = await tester.runAsync(() => ReceiptFonts.load(rootBundle));
      final r = await ReceiptsRepository(
        env.db,
        env.audit,
      ).receipt(saved.first.paymentId);
      final pdf = await tester.runAsync(() => buildReceiptPdf(r, fonts!));
      final names = RegExp(r'/BaseFont\s*/([^\s/>]+)')
          .allMatches(latin1.decode(pdf!))
          .map((m) => m[1])
          .toSet();
      expect(names, containsAll(['PirataOne-Regular', 'IM_FELL_English_SC']));
    });
  });
}
