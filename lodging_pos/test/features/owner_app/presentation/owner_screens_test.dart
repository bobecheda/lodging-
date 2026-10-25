import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/widgets/buttons.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';

import '../../../helpers/fake_owner_cloud.dart';
import '../../../helpers/fixtures.dart' show tapKey, enterKey;
import 'owner_app_test.dart' show pumpOwnerApp, phone, smallPhone;

/// owner-app-2 on the phone: Prices (Figma "06"), Money ("04") and Beds
/// ("05").
void main() {
  final now = nairobiInstant(2026, 10, 24, 9, 30); // Saturday
  late FixedClock clock;
  late FakeOwnerCloud cloud;

  setUp(() {
    clock = FixedClock(now);
    cloud = FakeOwnerCloud(serverNow: () => clock.now())
      ..stored = FakeOwnerCloud.owner;
    seedOwnerLodging(cloud, now);
  });

  String text(WidgetTester tester, String key) {
    final finder = find.byKey(ValueKey(key));
    if (tester.widget(finder) case Text(:final data?)) return data;
    return [
      for (final t in tester.widgetList<Text>(
        find.descendant(of: finder, matching: find.byType(Text)),
      ))
        t.data,
    ].join(' ');
  }

  /// Scrolls [list] down until [key] is built and on screen (lists build
  /// lazily).
  Future<void> reveal(WidgetTester tester, String key, String list) =>
      tester.scrollUntilVisible(
        find.byKey(ValueKey(key)),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(ValueKey(list)),
              matching: find.byType(Scrollable),
            )
            .first,
      );

  Future<void> toTop(WidgetTester tester, String list) async {
    await tester.drag(find.byKey(ValueKey(list)), const Offset(0, 5000));
    await tester.pumpAndSettle();
  }

  Map<String, Object?> category(String id) =>
      cloud.table('bed_categories').singleWhere((c) => c['id'] == id);

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<AppButton>(find.byKey(ValueKey(key))).onPressed != null;

  group('Prices', () {
    Future<void> open(WidgetTester tester, {Size size = phone}) async {
      await pumpOwnerApp(tester, cloud, clock, size: size);
      await tapKey(tester, 'owner.nav.prices');
    }

    testWidgets('the request and every category, in the desk’s order', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('REQUEST FROM GRACE (SUPERVISOR)'), findsOneWidget);
      expect(
        text(tester, 'priceRequest.reason.pr-1'),
        '“Other lodgings nearby charge 800.” · today 09:15',
      );
      expect(text(tester, 'owner.price.c-2.value'), 'KES 1,000'); // VIP first
      expect(text(tester, 'owner.price.c-1'), contains('2 beds'));
      expect(
        text(tester, 'owner.price.c-3'),
        contains('Closed · open it again on the desk'),
      );
      await tapKey(tester, 'owner.price.c-3');
      expect(find.byKey(const ValueKey('editPrice.sheet')), findsNothing);
    });

    testWidgets('Approve: the price changes in the cloud, with its two audit '
        'rows under one operation', (tester) async {
      await open(tester);
      clock.advance(const Duration(minutes: 1));
      await tapKey(tester, 'priceRequest.approve.pr-1');
      expect(
        text(tester, 'priceRequest.done'),
        'Deluxe is now KES 750 for new check-ins.',
      );
      expect(category('c-1')['price_per_night'], 750);
      final decision = cloud.table('price_decisions').single;
      expect(
        (decision['decision'], decision['device_id'], decision['decided_at']),
        (
          'approved',
          'phone-install-1',
          now.add(const Duration(minutes: 1)).toIso8601String(),
        ),
      );
      final audit = cloud.table('audit_log');
      expect(
        [for (final a in audit) a['action']],
        ['price.approve', 'price.update'],
      );
      expect(audit.first['operation_id'], audit.last['operation_id']);
      expect(
        find.byKey(const ValueKey('priceRequest.card.pr-1')),
        findsNothing,
      );
      expect(text(tester, 'owner.price.c-1.value'), 'KES 750');
    });

    testWidgets('Reject asks for the reason the supervisor sees', (
      tester,
    ) async {
      await open(tester);
      await tapKey(tester, 'priceRequest.reject.pr-1');
      await tapKey(tester, 'priceReject.reject');
      expect(
        find.text('Give a reason for rejecting the price change.'),
        findsOneWidget,
      );
      await enterKey(tester, 'priceReject.reason', 'Not this month');
      await tapKey(tester, 'priceReject.reject');
      final decision = cloud.table('price_decisions').single;
      expect(
        (decision['decision'], decision['note']),
        ('rejected', 'Not this month'),
      );
      expect(cloud.table('audit_log').single['action'], 'price.reject');
      expect(category('c-1')['price_per_night'], 700);
    });

    testWidgets('editing the price while a request is open makes it stale: '
        'Approve off, the desk’s wording, Reject still there', (tester) async {
      await open(tester);
      await tapKey(tester, 'owner.price.c-1');
      expect(find.text('Now KES 700 · 2 beds'), findsOneWidget);
      await enterKey(tester, 'editPrice.price', '800');
      await tester.pump();
      expect(
        text(tester, 'editPrice.change'),
        'Deluxe: 700 → 800 (+100 a night). Applies to new check-ins only.',
      );
      await tapKey(tester, 'editPrice.save');
      expect(category('c-1')['price_per_night'], 800);
      expect(cloud.table('audit_log').single['action'], 'price.update');
      expect(
        text(tester, 'priceRequest.stale.pr-1'),
        'Deluxe is now KES 800, not 700. Reject this request or ask for a '
        'new one.',
      );
      expect(enabled(tester, 'priceRequest.approve.pr-1'), isFalse);
      expect(enabled(tester, 'priceRequest.reject.pr-1'), isTrue);
    });

    testWidgets('whole KES above 0, not the same price; over 50% asks "Are '
        'you sure?" first', (tester) async {
      await open(tester);
      await tapKey(tester, 'owner.price.c-2');
      await enterKey(tester, 'editPrice.price', '0');
      await tapKey(tester, 'editPrice.save');
      expect(find.text('The price must be at least KES 1.'), findsOneWidget);
      await enterKey(tester, 'editPrice.price', '1000');
      await tapKey(tester, 'editPrice.save');
      expect(find.text('That’s already the price.'), findsOneWidget);

      await enterKey(tester, 'editPrice.price', '1600');
      await tapKey(tester, 'editPrice.save');
      expect(
        find.text(
          'Are you sure? VIP goes from KES 1,000 to KES 1,600 a night, 60% '
          'more.',
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'editPrice.sure.cancel');
      expect(category('c-2')['price_per_night'], 1000);
      await tapKey(tester, 'editPrice.save');
      await tapKey(tester, 'editPrice.sure.save');
      expect(category('c-2')['price_per_night'], 1600);
    });

    testWidgets('an edit made at the desk first wins: where and when, '
        'nothing overwritten', (tester) async {
      await open(tester);
      cloud.setPriceAtDesk(
        'c-1',
        750,
        now.subtract(const Duration(minutes: 1)),
      );
      await tapKey(tester, 'owner.price.c-1');
      await enterKey(tester, 'editPrice.price', '800');
      await tapKey(tester, 'editPrice.save');
      expect(
        find.text(
          'Deluxe was changed to KES 750 on the desk · Sat 24 Oct, 09:29. '
          'Check it and save again.',
        ),
        findsOneWidget,
      );
      expect(category('c-1')['price_per_night'], 750);
      expect(cloud.table('audit_log'), isEmpty);
    });

    testWidgets('decided at the desk first: who and when', (tester) async {
      await open(tester);
      cloud.table('price_decisions').add({
        'id': 'pd-desk',
        'request_id': 'pr-1',
        'decision': 'approved',
        'note': null,
        'decided_by': 'u-owner',
        'decided_at': now
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
        'device_id': 'dev-1',
      });
      await tapKey(tester, 'priceRequest.approve.pr-1');
      expect(
        text(tester, 'priceRequest.problem'),
        'Already decided by Amina Owner · Sat 24 Oct, 09:29 (approved).',
      );
      expect(cloud.table('price_decisions'), hasLength(1));
    });

    testWidgets('offline: approving and editing are refused', (tester) async {
      await open(tester);
      cloud.offline = true;
      await tapKey(tester, 'priceRequest.approve.pr-1');
      expect(
        text(tester, 'priceRequest.problem'),
        'Approving needs an internet connection.',
      );
      await tapKey(tester, 'owner.price.c-1');
      await enterKey(tester, 'editPrice.price', '750');
      await tapKey(tester, 'editPrice.save');
      expect(
        find.text('Changing prices needs an internet connection.'),
        findsOneWidget,
      );
      expect(category('c-1')['price_per_night'], 700);
    });
  });

  group('Money', () {
    Future<void> open(WidgetTester tester, {Size size = phone}) async {
      await pumpOwnerApp(tester, cloud, clock, size: size);
      await tapKey(tester, 'owner.nav.money');
    }

    testWidgets('this month: net, received, refunds paid, the same point in '
        'September, the void left out; cash against M-Pesa; nights let', (
      tester,
    ) async {
      await open(tester);
      expect(
        text(tester, 'owner.money.fresh'),
        'Up to the desk’s last sync, 09:27 · 3 changes not sent yet.',
      );
      expect(find.text('OCTOBER SO FAR · NET'), findsOneWidget);
      expect(text(tester, 'owner.money.net'), 'KES 4,200');
      expect(text(tester, 'owner.money.received'), 'KES 4,200');
      expect(text(tester, 'owner.money.refunds'), '− KES 0');
      expect(find.text('Same point in September'), findsOneWidget);
      expect(text(tester, 'owner.money.before'), 'KES 0');
      expect(
        text(tester, 'owner.money.voided'),
        'KES 700 voided, not counted.',
      );
      await reveal(tester, 'owner.money.mpesa', 'owner.money');
      expect(find.text('Cash · 67%'), findsOneWidget);
      expect(text(tester, 'owner.money.cash'), 'KES 2,800');
      expect(text(tester, 'owner.money.mpesa'), 'KES 1,400');
      // Deluxe: the closed stay's 22 and 23 Oct (2 refunded), the open
      // stay's 23 and 24 Oct.
      await reveal(tester, 'owner.money.categoriesNote', 'owner.money');
      expect(text(tester, 'owner.money.nights.Deluxe'), '4 bed-nights');
      expect(text(tester, 'owner.money.value.Deluxe'), 'KES 2,800');
      expect(
        text(tester, 'owner.money.categoriesNote'),
        'Value of nights stayed in this period. Net above counts money on '
        'the day it was paid, so the two won’t match.',
      );
    });

    testWidgets('today and this week; every day as text, each bar named', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(tester);
      await tapKey(tester, 'owner.money.period.today');
      expect(find.text('TODAY SO FAR · NET'), findsOneWidget);
      expect(text(tester, 'owner.money.net'), 'KES 1,400');
      expect(find.text('Same time last Saturday'), findsOneWidget);
      await reveal(tester, 'owner.money.nights.Deluxe', 'owner.money');
      expect(text(tester, 'owner.money.nights.Deluxe'), '1 bed-night');
      await toTop(tester, 'owner.money');
      await tapKey(tester, 'owner.money.period.week');
      expect(find.text('THIS WEEK SO FAR · NET'), findsOneWidget);
      expect(find.text('Same point last week'), findsOneWidget);

      await reveal(tester, 'owner.money.eachDay', 'owner.money');
      expect(
        text(tester, 'owner.money.dailySummary'),
        'Best day: Thu 22 Oct, KES 2,800. Today so far: KES 1,400.',
      );
      expect(find.bySemanticsLabel('Thu 22 Oct · KES 2,800'), findsOneWidget);
      expect(find.bySemanticsLabel('Today so far · KES 1,400'), findsOneWidget);
      expect(find.byKey(const ValueKey('owner.money.day.12')), findsNothing);
      await tapKey(tester, 'owner.money.eachDay');
      await reveal(tester, 'owner.money.day.11', 'owner.money');
      expect(text(tester, 'owner.money.day.13'), 'Today so far · KES 1,400');
      expect(text(tester, 'owner.money.day.12'), 'Fri 23 Oct · KES 0');
      expect(text(tester, 'owner.money.day.11'), 'Thu 22 Oct · KES 2,800');
      await reveal(tester, 'owner.money.day.0', 'owner.money');
      expect(text(tester, 'owner.money.day.0'), 'Sun 11 Oct · KES 0');
      semantics.dispose();
    });

    testWidgets('days end at Nairobi midnight by the server’s clock, not the '
        'phone’s: 23:59 is yesterday, 00:01 today', (tester) async {
      final server = nairobiInstant(2026, 10, 24, 0, 30);
      clock = FixedClock(server.subtract(const Duration(hours: 2)));
      cloud.serverNow = () => clock.now().add(const Duration(hours: 2));
      cloud.table('payments')
        ..clear()
        ..addAll([
          {
            'id': 'p-late',
            'receipt_number': 'R-000050',
            'received_at': nairobiInstant(
              2026,
              10,
              23,
              23,
              59,
            ).toIso8601String(),
            'amount': 900,
            'method': 'cash',
          },
          {
            'id': 'p-early',
            'receipt_number': 'R-000051',
            'received_at': nairobiInstant(2026, 10, 24, 0, 1).toIso8601String(),
            'amount': 300,
            'method': 'cash',
          },
        ]);
      cloud.table('voids').clear();
      await open(tester);
      await tapKey(tester, 'owner.money.period.today');
      expect(text(tester, 'owner.money.net'), 'KES 300');
      expect(find.textContaining('Saturday 24 October'), findsOneWidget);
    });
  });

  group('Beds', () {
    Future<void> open(WidgetTester tester, {Size size = phone}) async {
      await pumpOwnerApp(tester, cloud, clock, size: size);
      await tapKey(tester, 'owner.nav.beds');
    }

    testWidgets(
      'statuses from stays and the server’s time; no guest anywhere',
      (tester) async {
        await open(tester);
        expect(text(tester, 'owner.beds.count.occupied'), contains('1'));
        expect(text(tester, 'owner.beds.bed.b-5a'), 'Occupied');
        expect(text(tester, 'owner.beds.bed.b-5b'), 'Needs cleaning');
        expect(
          find.byKey(const ValueKey('owner.beds.overstays')),
          findsNothing,
        );
        expect(find.textContaining('Jane'), findsNothing);
        expect(find.textContaining('Peter'), findsNothing);
      },
    );

    testWidgets('an overstay: where and how long past the grace period, '
        'never who; a status filters the rooms', (tester) async {
      cloud.table('stays').firstWhere((s) => s['id'] == 'st-2')['paid_until'] =
          now.subtract(const Duration(hours: 2)).toIso8601String();
      await open(tester);
      expect(find.text('1 overstay'), findsOneWidget);
      expect(
        text(tester, 'owner.beds.overstay.0'),
        'Room 5 A · paid to 07:30, now 1 h 30 min past the grace period.',
      );
      expect(text(tester, 'owner.beds.bed.b-5a'), 'Overstay');
      expect(find.textContaining('Jane'), findsNothing);

      await tapKey(tester, 'owner.beds.count.toClean');
      expect(text(tester, 'owner.beds.filter'), 'Showing Needs cleaning only.');
      expect(find.byKey(const ValueKey('owner.beds.bed.b-5a')), findsNothing);
      expect(find.byKey(const ValueKey('owner.beds.bed.b-5b')), findsOneWidget);
      await tapKey(tester, 'owner.beds.showAll');
      expect(find.byKey(const ValueKey('owner.beds.bed.b-5a')), findsOneWidget);
    });
  });

  group('fits a phone', () {
    for (final size in [smallPhone, phone]) {
      final label = '${size.width.toInt()}×${size.height.toInt()}';
      testWidgets('$label: Prices, its sheet and dialogs; Money every '
          'period; Beds with an overstay', (tester) async {
        cloud
            .table('stays')
            .firstWhere((s) => s['id'] == 'st-2')['paid_until'] = now
            .subtract(const Duration(hours: 30))
            .toIso8601String();
        await pumpOwnerApp(tester, cloud, clock, size: size);

        await tapKey(tester, 'owner.nav.prices');
        await tapKey(tester, 'priceRequest.reject.pr-1');
        await tapKey(tester, 'priceReject.cancel');
        await tapKey(tester, 'owner.price.c-1');
        await enterKey(tester, 'editPrice.price', '1200');
        await tapKey(tester, 'editPrice.save');
        await tapKey(tester, 'editPrice.sure.cancel');
        await tapKey(tester, 'editPrice.cancel');

        await tapKey(tester, 'owner.nav.money');
        for (final p in ['today', 'week', 'month']) {
          await tapKey(tester, 'owner.money.period.$p');
        }
        await reveal(tester, 'owner.money.eachDay', 'owner.money');
        await tapKey(tester, 'owner.money.eachDay');
        await tester.drag(
          find.byKey(const ValueKey('owner.money')),
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();

        await tapKey(tester, 'owner.nav.beds');
        await tester.drag(
          find.byKey(const ValueKey('owner.beds')),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        // Any overflow fails the test on its own.
        expect(tester.takeException(), isNull);
      });
    }
  });
}
