import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/prices_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/setup/presentation/prices_screen.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount supervisor;

  setUp(() async {
    env = TestEnv();
    supervisor = await env.createFirstSupervisor(testSetup);
  });
  tearDown(() => env.close());

  PricesRepository prices() => PricesRepository(env.db, env.audit);

  /// Signs in as the supervisor (or [asOwner], the owner, who edits prices)
  /// and opens Prices & settings from the sidebar.
  Future<ProviderContainer> openPrices(
    WidgetTester tester, {
    bool asOwner = false,
  }) async {
    final app = await pumpDeskApp(tester, env);
    if (asOwner) {
      await signInAs(tester, 'owner', 'owner-pass');
    } else {
      await signInAs(tester, 'supervisor', 'super-pass');
    }
    await tapKey(tester, 'nav.${Routes.adminPrices}');
    expect(locationOf(app), Routes.adminPrices);
    return app;
  }

  Future<int> priceOf(String id) async => (await prices().categories())
      .firstWhere((u) => u.category.id == id)
      .category
      .pricePerNight;

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('shows categories with their beds, and the settings', (
    tester,
  ) async {
    await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '3',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: SeedIds.deluxe,
      ),
    );
    await openPrices(tester);
    expect(find.text('Prices and settings'), findsOneWidget);
    for (final name in ['VIP', 'Deluxe', 'Comfort', 'Normal']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(textOf(tester, 'categories.beds.${SeedIds.deluxe}'), '2');
    expect(textOf(tester, 'categories.beds.${SeedIds.vip}'), '0');
    expect(find.text('10:00'), findsOneWidget);
    expect(
      find.textContaining('Changes apply immediately to every guest.'),
      findsOneWidget,
    );
    expect(find.textContaining('next receipt R-000001'), findsOneWidget);
  });

  testWidgets('a changed price shows "was", and saves only after confirming', (
    tester,
  ) async {
    await openPrices(tester, asOwner: true);
    await enterKey(tester, 'price.${SeedIds.deluxe}', '750');
    await tester.pump();
    expect(textOf(tester, 'price.was.${SeedIds.deluxe}'), 'was 700');

    // Cancel: nothing saved, the edit stays.
    await tapKey(tester, 'prices.save');
    expect(
      textOf(tester, 'confirm.change.${SeedIds.deluxe}'),
      'Deluxe: 700 → 750',
    );
    expect(
      find.text(
        'These prices apply to new check-ins only. Guests already staying '
        'keep their price.',
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'confirm.cancel');
    expect(await priceOf(SeedIds.deluxe), 700);
    expect(find.byKey(ValueKey('price.was.${SeedIds.deluxe}')), findsOneWidget);

    // Confirm: saved and audited with old and new.
    await tapKey(tester, 'prices.save');
    await tapKey(tester, 'confirm.ok');
    expect(await priceOf(SeedIds.deluxe), 750);
    expect(find.byKey(ValueKey('price.was.${SeedIds.deluxe}')), findsNothing);
    expect(textOf(tester, 'prices.saved'), 'Price saved.');
    expect(await env.auditFor('price.update'), hasLength(1));
  });

  testWidgets('a price over 100,000 is refused before any dialog', (
    tester,
  ) async {
    await openPrices(tester, asOwner: true);
    await enterKey(tester, 'price.${SeedIds.vip}', '100001');
    await tapKey(tester, 'prices.save');
    expect(find.text('The price can be at most KES 100,000.'), findsOneWidget);
    expect(find.byKey(const ValueKey('confirm.ok')), findsNothing);
    expect(await priceOf(SeedIds.vip), 1000);
  });

  testWidgets('adds a category; a name in use is refused', (tester) async {
    await openPrices(tester, asOwner: true);
    await tapKey(tester, 'categories.add');
    await enterKey(tester, 'categories.newName', 'deluxe');
    await enterKey(tester, 'categories.newPrice', '900');
    await tapKey(tester, 'categories.confirmAdd');
    expect(find.text('Deluxe already exists.'), findsOneWidget);

    await enterKey(tester, 'categories.newName', ' Family ');
    await tapKey(tester, 'categories.confirmAdd');
    expect(find.text('Family'), findsOneWidget);
    expect(find.byKey(const ValueKey('categories.newName')), findsNothing);
    expect(await env.auditFor('category.create'), hasLength(1));
  });

  testWidgets('Close is disabled with the reason while beds use a category; '
      'an unused one closes and reopens', (tester) async {
    await RoomsRepository(env.db, env.audit).createRoom(
      supervisor,
      const NewRoom(
        number: '3',
        floor: null,
        notes: null,
        bedACategoryId: SeedIds.deluxe,
        bedBCategoryId: null,
      ),
    );
    await openPrices(tester, asOwner: true);

    final close = tester.widget<TextButton>(
      find.byKey(ValueKey('categories.close.${SeedIds.deluxe}')),
    );
    expect(close.onPressed, isNull);
    expect(
      tester
          .widget<Tooltip>(
            find.byKey(ValueKey('categories.blocker.${SeedIds.deluxe}')),
          )
          .message,
      '1 bed uses Deluxe. Move it to another category first.',
    );

    await tapKey(tester, 'categories.close.${SeedIds.vip}');
    expect(find.text('CLOSED'), findsOneWidget);
    await tapKey(tester, 'categories.reopen.${SeedIds.vip}');
    expect(find.text('CLOSED'), findsNothing);
    expect(await env.auditFor('category.update'), hasLength(2));
  });

  testWidgets('saves settings; the new lodging name reaches the sidebar', (
    tester,
  ) async {
    await openPrices(tester);
    await tapKey(tester, 'settings.checkoutTime.10:00');
    await tester.tap(find.text('09:30').last);
    await tester.pumpAndSettle();
    await enterKey(tester, 'settings.grace', '45');
    await enterKey(tester, 'settings.receiptPrefix', 'sun');
    await tester.pump();
    expect(find.textContaining('next receipt SUN-000001'), findsOneWidget);
    await enterKey(tester, 'settings.lodgingName', 'Hilltop Lodge');
    await tapKey(tester, 'settings.save');

    expect(textOf(tester, 'settings.saved'), 'Settings saved.');
    final s = await prices().settings();
    expect(s.checkoutTime.format(), '09:30');
    expect(
      (s.graceMinutes, s.receiptPrefix, s.lodgingName),
      ('45', 'SUN', 'Hilltop Lodge'),
    );
    expect(find.text('Hilltop Lodge'), findsWidgets); // sidebar brand
  });

  testWidgets('settings outside their ranges are refused with the range', (
    tester,
  ) async {
    await openPrices(tester);
    await enterKey(tester, 'settings.grace', '181');
    await enterKey(tester, 'settings.idleLock', '61');
    await tapKey(tester, 'settings.save');
    expect(find.text('Enter whole minutes from 0 to 180.'), findsOneWidget);
    expect(find.text('Enter whole minutes from 1 to 60.'), findsOneWidget);
    expect((await prices().settings()).graceMinutes, '60');
  });

  testWidgets("the supervisor's prices are read-only, with why; the owner's "
      'Prices has no settings', (tester) async {
    await openPrices(tester);
    expect(
      find.text(
        'Only the owner changes prices. Use “Request a change” to ask; the '
        'owner approves or rejects it.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('prices.save')), findsNothing);
    expect(find.byKey(const ValueKey('categories.add')), findsNothing);
  });

  testWidgets("the owner's Prices: no settings, no backups", (tester) async {
    await openPrices(tester, asOwner: true);
    expect(find.text('Prices'), findsWidgets);
    expect(find.text('Prices and settings'), findsNothing);
    expect(find.byKey(const ValueKey('settings.save')), findsNothing);
    expect(find.byKey(const ValueKey('prices.readOnly')), findsNothing);
  });

  testWidgets('a receptionist cannot open Prices & settings', (tester) async {
    await env.addReceptionist('desk');
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await enterKey(tester, 'shift.float', '500');
    await tapKey(tester, 'shift.submit');
    expect(find.text('Prices & settings'), findsNothing);

    app.read(routerProvider).go(Routes.adminPrices);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.home);
    expect(find.byType(PricesScreen), findsNothing);
  });
}
