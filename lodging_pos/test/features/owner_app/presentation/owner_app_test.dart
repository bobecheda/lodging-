import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/dashboard/domain/dashboard.dart';
import 'package:lodging_pos/features/owner_app/presentation/owner_app.dart';
import 'package:lodging_pos/features/owner_app/presentation/owner_providers.dart';

import '../../../helpers/fake_owner_cloud.dart';
import '../../../helpers/fixtures.dart';

/// Phone sizes the owner app must fit (Android small and common).
const smallPhone = Size(360, 640);
const phone = Size(412, 915);

/// Starts the owner's app on [cloud] at [clock]'s time.
Future<ProviderContainer> pumpOwnerApp(
  WidgetTester tester,
  FakeOwnerCloud cloud,
  FixedClock clock, {
  Size size = phone,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      ownerCloudProvider.overrideWithValue(cloud),
      clockProvider.overrideWithValue(clock),
      ownerRefreshIntervalProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const OwnerApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

String ownerLocation(ProviderContainer app) =>
    app.read(ownerRouterProvider).state.matchedLocation;

void main() {
  final now = nairobiInstant(2026, 10, 24, 9, 30);
  late FixedClock clock;
  late FakeOwnerCloud cloud;

  setUp(() {
    clock = FixedClock(now);
    cloud = FakeOwnerCloud(serverNow: () => clock.now());
    seedOwnerLodging(cloud, now);
  });

  /// The text of [key]: a Text, or the texts inside it (a Note).
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

  Future<void> signIn(WidgetTester tester) async {
    await enterKey(tester, 'ownerSignIn.email', testOwnerEmail);
    await enterKey(tester, 'ownerSignIn.password', testOwner.password);
    await tapKey(tester, 'ownerSignIn.submit');
  }

  testWidgets('sign in: a wrong password is refused; then Today with the '
      'header and everything that needs the owner', (tester) async {
    final app = await pumpOwnerApp(tester, cloud, clock);
    expect(ownerLocation(app), OwnerRoutes.signIn);

    await enterKey(tester, 'ownerSignIn.email', testOwnerEmail);
    await enterKey(tester, 'ownerSignIn.password', 'not-it');
    await tapKey(tester, 'ownerSignIn.submit');
    expect(text(tester, 'ownerSignIn.problem'), 'Wrong email or password.');

    await enterKey(tester, 'ownerSignIn.password', testOwner.password);
    await tapKey(tester, 'ownerSignIn.submit');
    expect(ownerLocation(app), OwnerRoutes.today);

    expect(find.text('UB40'), findsOneWidget);
    expect(text(tester, 'owner.date'), formatLongDate(now));
    expect(text(tester, 'owner.updated'), 'Updated just now');
    expect(text(tester, 'owner.desk'), 'Desk online · 3 changes waiting');

    expect(find.text('4'), findsWidgets); // the attention badge
    expect(find.byKey(const ValueKey('today.attention.refund.rf-1')), findsOne);
    expect(find.byKey(const ValueKey('today.attention.price.pr-1')), findsOne);
    expect(find.byKey(const ValueKey('today.attention.short.s-1')), findsOne);
    expect(find.text('Cash short at shift close'), findsOneWidget);
    expect(find.text('Payment voided · R-000043'), findsOneWidget);
    // Today: 1,400 by M-Pesa; the voided 700 doesn't count.
    expect(text(tester, 'today.money.total'), 'KES 1,400');
    expect(text(tester, 'today.beds.inUse'), '1 of 2');

    // Between reloads the header says how old the figures are.
    clock.advance(const Duration(minutes: 4));
    await tapKey(tester, 'owner.nav.more');
    expect(text(tester, 'owner.updated'), 'Updated 4 min ago');
  });

  testWidgets('the refund: masked phone, the receipts, then Approve, in the '
      'cloud with its audit row', (tester) async {
    final app = await pumpOwnerApp(tester, cloud, clock);
    await signIn(tester);
    await tapKey(tester, 'today.attention.refund.rf-1');
    expect(ownerLocation(app), OwnerRoutes.refund);

    expect(text(tester, 'refund.guest'), startsWith('0711 ••• 482 · Room 5'));
    expect(text(tester, 'refund.paid.0'), '4 nights × KES 700 · R-000041');
    expect(text(tester, 'refund.amount'), 'KES 1,400');
    expect(find.textContaining('0711000482'), findsNothing);

    clock.advance(const Duration(minutes: 1));
    await tapKey(tester, 'refund.approve');
    expect(find.byKey(const ValueKey('refund.decided')), findsOneWidget);
    expect(find.byKey(const ValueKey('refund.approve')), findsNothing);

    final decision = cloud.table('refund_decisions').single;
    expect(decision['decision'], 'approved');
    expect(decision['device_id'], 'phone-install-1');
    // Stamped with the server's time.
    expect(
      decision['decided_at'],
      now.add(const Duration(minutes: 1)).toIso8601String(),
    );
    final audit = cloud.table('audit_log').single;
    expect(audit['action'], 'refund.approve');
    expect(audit['user_id'], 'u-owner');
    expect(audit['entity_id'], decision['id']);
    expect(jsonDecode(audit['after_json']! as String)['refund_id'], 'rf-1');

    await tapKey(tester, 'refund.back');
    expect(
      find.byKey(const ValueKey('today.attention.refund.rf-1')),
      findsNothing,
    );
  });

  testWidgets('Reject needs a reason, which goes to the cloud', (tester) async {
    await pumpOwnerApp(tester, cloud, clock);
    await signIn(tester);
    await tapKey(tester, 'today.attention.refund.rf-1');
    await tapKey(tester, 'refund.reject');
    await enterKey(tester, 'refund.reason', 'Guest stays on');
    await tapKey(tester, 'refund.reason.reject');
    final decision = cloud.table('refund_decisions').single;
    expect(decision['decision'], 'rejected');
    expect(decision['note'], 'Guest stays on');
    expect(cloud.table('audit_log').single['action'], 'refund.reject');
  });

  testWidgets('decided at the desk first: the desk\'s decision is shown', (
    tester,
  ) async {
    await pumpOwnerApp(tester, cloud, clock);
    await signIn(tester);
    await tapKey(tester, 'today.attention.refund.rf-1');
    cloud.decideElsewhere('rf-1', at: now.subtract(const Duration(minutes: 1)));
    await tapKey(tester, 'refund.approve');
    expect(
      text(tester, 'refund.problem'),
      'Already decided by Amina Owner · Sat 24 Oct, 09:29 (approved).',
    );
    expect(cloud.table('refund_decisions'), hasLength(1));
  });

  testWidgets('offline: Today stays as last loaded, marked offline; '
      'deciding is refused', (tester) async {
    final app = await pumpOwnerApp(tester, cloud, clock);
    await signIn(tester);
    await tapKey(tester, 'today.attention.refund.rf-1');
    cloud.offline = true;
    await tapKey(tester, 'refund.approve');
    expect(
      text(tester, 'refund.problem'),
      'Approving needs an internet connection.',
    );
    expect(cloud.table('refund_decisions'), isEmpty);

    await tapKey(tester, 'refund.back');
    clock.advance(const Duration(minutes: 3));
    await app.read(ownerTodayDataProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(text(tester, 'owner.updated'), 'Offline · showing today 09:30');
    expect(text(tester, 'today.money.total'), 'KES 1,400');

    cloud.offline = false;
    await tester.fling(
      find.byKey(const ValueKey('owner.today')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(text(tester, 'owner.updated'), 'Updated just now');
  });

  testWidgets('stays signed in: the next start opens Today; Sign out forgets '
      'it and drops the figures', (tester) async {
    cloud.stored = FakeOwnerCloud.owner;
    final app = await pumpOwnerApp(tester, cloud, clock);
    expect(ownerLocation(app), OwnerRoutes.today);

    await tapKey(tester, 'owner.nav.more');
    expect(text(tester, 'owner.more.email'), testOwnerEmail);
    await tapKey(tester, 'owner.signOut');
    expect(ownerLocation(app), OwnerRoutes.signIn);
    expect(cloud.stored, isNull);
    expect(app.read(ownerTodayDataProvider).value, isNull);
  });

  testWidgets('a desk not heard from for 12 minutes shows offline', (
    tester,
  ) async {
    cloud.table('desk_status').single['reported_at'] = now
        .subtract(const Duration(minutes: 12))
        .toIso8601String();
    await pumpOwnerApp(tester, cloud, clock);
    await signIn(tester);
    expect(text(tester, 'owner.desk'), 'Desk offline · last seen today 09:18');
  });

  group('fits a phone', () {
    for (final size in [smallPhone, phone]) {
      final label = '${size.width.toInt()}×${size.height.toInt()}';
      testWidgets('$label: sign in, Today, the refund, More', (tester) async {
        final app = await pumpOwnerApp(tester, cloud, clock, size: size);
        await signIn(tester);
        expect(ownerLocation(app), OwnerRoutes.today);
        await tester.drag(
          find.byKey(const ValueKey('owner.today')),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('owner.today')),
          const Offset(0, 2000),
        );
        await tester.pumpAndSettle();
        await tapKey(tester, 'today.attention.refund.rf-1');
        await tapKey(tester, 'refund.approve');
        await tapKey(tester, 'owner.nav.more');
        await tapKey(tester, 'owner.signOut');
        await enterKey(tester, 'ownerSignIn.password', 'not-it');
        await tapKey(tester, 'ownerSignIn.submit');
        // Any overflow fails the test on its own.
        expect(tester.takeException(), isNull);
      });
    }
  });
}
