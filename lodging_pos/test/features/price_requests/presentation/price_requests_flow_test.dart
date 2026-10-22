import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/price_requests/data/price_requests_repository.dart';
import 'package:lodging_pos/features/price_requests/domain/price_request.dart';
import 'package:lodging_pos/features/setup/data/prices_repository.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;
  late UserAccount supervisor;
  late PriceRequestsRepository requests;
  late PricesRepository prices;
  const deluxe = SeedIds.deluxe;

  setUp(() async {
    env = TestEnv();
    env.clock.set(nairobiInstant(2026, 10, 21, 9, 15)); // Wed 09:15
    supervisor = await env.createFirstSupervisor(testSetup);
    owner = env.owner!;
    requests = PriceRequestsRepository(env.db, env.audit);
    prices = PricesRepository(env.db, env.audit);
  });
  tearDown(() => env.close());

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  Future<String> askDeluxe({String? reason}) => requests.request(
    supervisor,
    categoryId: deluxe,
    newPrice: 750,
    reason: reason,
  );

  Future<PriceRequestStatus> status(String id) async =>
      (await requests.view(id)).status;

  /// The text of the Note with [key].
  Finder note(String key, String message) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.text(message),
  );

  bool enabled(WidgetTester tester, String key) =>
      tester
          .widget<TextButton>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed !=
      null;

  group('the supervisor', () {
    testWidgets('asks for a change: the price is checked, the line shows the '
        'change; then Waiting, and withdrawing frees the category', (
      tester,
    ) async {
      await pumpDeskApp(tester, env);
      await signInAs(tester, 'supervisor', 'super-pass');
      await tapKey(tester, 'nav.${Routes.adminPrices}');
      expect(
        text(tester, 'prices.readOnly'),
        startsWith('Only the owner changes prices.'),
      );
      expect(find.byKey(const ValueKey('priceRequests.empty')), findsOne);

      await tapKey(tester, 'categories.request.$deluxe');
      expect(find.text('Deluxe · ask for a new price'), findsOneWidget);
      expect(find.text('Now KES 700 · 0 beds'), findsOneWidget);
      await tapKey(tester, 'priceRequest.send');
      expect(find.text('Enter a price.'), findsOneWidget);
      await enterKey(tester, 'priceRequest.price', '700');
      await tapKey(tester, 'priceRequest.send');
      expect(find.text('That’s already the price.'), findsOneWidget);

      await enterKey(tester, 'priceRequest.price', '750');
      await tester.pump();
      expect(
        text(tester, 'priceRequest.preview'),
        'Deluxe: 700 → 750 (+50 a night). Applies to new check-ins only, '
        'once the owner approves.',
      );
      await enterKey(tester, 'priceRequest.reason', 'Others charge 800');
      await tapKey(tester, 'priceRequest.send');
      expect(find.byKey(const ValueKey('priceRequest.dialog')), findsNothing);

      final id = (await requests.waiting()).single.id;
      expect(
        find.descendant(
          of: find.byKey(ValueKey('categories.waiting.$deluxe')),
          matching: find.text('WAITING · KES 750'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('categories.request.$deluxe')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('priceRequests.status.$id')),
          matching: find.text('WAITING FOR OWNER APPROVAL'),
        ),
        findsOneWidget,
      );
      expect(
        text(tester, 'priceRequests.detail.$id'),
        'Asked by Grace · today 09:15',
      );

      await tapKey(tester, 'priceRequests.withdraw.$id');
      expect(await status(id), PriceRequestStatus.withdrawn);
      expect(find.byKey(ValueKey('priceRequests.row.$id')), findsNothing);
      expect(find.byKey(ValueKey('categories.request.$deluxe')), findsOne);
    });

    testWidgets('sees a rejection with the owner’s reason, and a request '
        'ended by closing its category', (tester) async {
      final rejected = await requests.request(
        supervisor,
        categoryId: SeedIds.vip,
        newPrice: 1200,
      );
      await requests.decide(
        owner,
        rejected,
        approve: false,
        note: 'Not this month',
      );
      final closed = await askDeluxe();
      await prices.closeCategory(owner, deluxe);

      await pumpDeskApp(tester, env);
      await signInAs(tester, 'supervisor', 'super-pass');
      await tapKey(tester, 'nav.${Routes.adminPrices}');
      expect(
        text(tester, 'priceRequests.reason.$rejected'),
        '“Not this month”',
      );
      expect(
        text(tester, 'priceRequests.detail.$rejected'),
        'Rejected by Amina Owner · today 09:15',
      );
      expect(
        text(tester, 'priceRequests.detail.$closed'),
        'Withdrawn · category closed · today 09:15',
      );
      // A closed category can't be asked about.
      expect(find.byKey(ValueKey('categories.request.$deluxe')), findsNothing);
      expect(
        find.byKey(ValueKey('categories.request.${SeedIds.vip}')),
        findsOne,
      );
    });
  });

  group('the owner', () {
    testWidgets('from Today: the Price row and the Prices badge; approving '
        'changes the price at once', (tester) async {
      final id = await askDeluxe(reason: 'Others charge 800');
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      expect(find.text('Deluxe: 700 → 750'), findsOneWidget);
      expect(
        find.text('From Grace (supervisor) · today 09:15'),
        findsOneWidget,
      );
      expect(find.text('+50'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('nav.badge.${Routes.adminPrices}')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );

      await tapKey(tester, 'today.attention.price.$id');
      expect(locationOf(app), Routes.adminPrices);
      expect(find.text('REQUEST FROM GRACE (SUPERVISOR)'), findsOneWidget);
      expect(text(tester, 'priceRequest.change.$id'), 'KES 700 → 750');
      expect(
        text(tester, 'priceRequest.reason.$id'),
        '“Others charge 800” · today 09:15',
      );

      await tapKey(tester, 'priceRequest.approve.$id');
      expect(await status(id), PriceRequestStatus.approved);
      expect(
        note('priceRequest.done', 'Deluxe is now KES 750 for new check-ins.'),
        findsOneWidget,
      );
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('price.$deluxe')),
      );
      expect(input.controller!.text, '750');
      expect(find.byKey(ValueKey('priceRequest.card.$id')), findsNothing);
      // The badge shows nothing at zero.
      expect(
        find.descendant(
          of: find.byKey(ValueKey('nav.badge.${Routes.adminPrices}')),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    });

    testWidgets('Reject asks for a reason first; Cancel changes nothing', (
      tester,
    ) async {
      final id = await askDeluxe();
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'nav.${Routes.adminPrices}');
      expect(locationOf(app), Routes.adminPrices);

      await tapKey(tester, 'priceRequest.reject.$id');
      expect(find.text('Reject this price change?'), findsOneWidget);
      expect(
        find.text('Deluxe · KES 700 → 750. Grace will see your reason.'),
        findsOneWidget,
      );
      await tapKey(tester, 'priceReject.cancel');
      expect(await status(id), PriceRequestStatus.waiting);

      await tapKey(tester, 'priceRequest.reject.$id');
      await tapKey(tester, 'priceReject.reject');
      expect(
        find.text('Give a reason for rejecting the price change.'),
        findsOneWidget,
      );
      await enterKey(tester, 'priceReject.reason', 'Not this month');
      await tapKey(tester, 'priceReject.reject');
      expect(await status(id), PriceRequestStatus.rejected);
      expect(
        note(
          'priceRequest.done',
          'Request rejected. Grace will see your reason.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('priceRequest.none')), findsOneWidget);
    });

    testWidgets('a stale request: the note at once, Approve off, Reject '
        'still works', (tester) async {
      final id = await askDeluxe();
      await prices.savePrices(owner, {deluxe: 720});
      await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'nav.${Routes.adminPrices}');

      expect(
        find.descendant(
          of: find.byKey(ValueKey('priceRequest.stale.$id')),
          matching: find.text(
            'Deluxe is now KES 720, not 700. Reject this request or ask for '
            'a new one.',
          ),
        ),
        findsOneWidget,
      );
      expect(enabled(tester, 'priceRequest.approve.$id'), isFalse);
      expect(enabled(tester, 'priceRequest.reject.$id'), isTrue);
    });
  });
}
