import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/setup/presentation/rooms_screen.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount owner;

  setUp(() async {
    env = TestEnv();
    owner = await env.users.createFirstAdmin(testSetup);
  });
  tearDown(() => env.close());

  RoomsRepository rooms() => RoomsRepository(env.db, env.audit);

  Future<RoomSummary> seedRoom(String number, {bool twoBeds = true}) =>
      rooms().createRoom(
        owner,
        NewRoom(
          number: number,
          floor: 'Ground',
          notes: null,
          bedACategoryId: SeedIds.normal,
          bedBCategoryId: twoBeds ? SeedIds.deluxe : null,
        ),
      );

  /// Signs in as the owner and opens Rooms & beds from the sidebar.
  Future<ProviderContainer> openRooms(WidgetTester tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    expect(find.text('SETUP · OWNER ONLY'), findsOneWidget);
    await tapKey(tester, 'nav.${Routes.adminRooms}');
    expect(locationOf(app), Routes.adminRooms);
    return app;
  }

  Future<void> pick(WidgetTester tester, String key, String option) async {
    await tapKey(tester, key);
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('empty: says how to start', (tester) async {
    await openRooms(tester);
    expect(find.text('Rooms and beds'), findsOneWidget);
    expect(find.textContaining('No rooms yet'), findsOneWidget);
    expect(find.text('0 rooms · 0 beds active'), findsOneWidget);
  });

  testWidgets('adds a 2-bed room from the side panel', (tester) async {
    await openRooms(tester);
    await tapKey(tester, 'rooms.add');
    expect(find.text('Add a room'), findsOneWidget);

    await enterKey(tester, 'add.number', ' 5 ');
    await enterKey(tester, 'add.floor', 'Ground');
    await tapKey(tester, 'choice.2');
    await pick(tester, 'add.bedA', 'Normal · KES 500');
    await pick(tester, 'add.bedB', 'Deluxe · KES 700');
    await tapKey(tester, 'add.save');

    expect(find.text('Add a room'), findsNothing);
    expect(find.text('Room 5'), findsOneWidget);
    expect(find.text('A · Normal'), findsOneWidget);
    expect(find.text('B · Deluxe'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('1 room · 2 beds active'), findsOneWidget);
    expect(await env.auditFor('room.create'), hasLength(1));
  });

  testWidgets('a duplicate number is refused with a message', (tester) async {
    await seedRoom('5');
    await openRooms(tester);
    await tapKey(tester, 'rooms.add');
    await enterKey(tester, 'add.number', '5');
    await pick(tester, 'add.bedA', 'VIP · KES 1,000');
    await tapKey(tester, 'add.save');
    expect(
      find.text('Room 5 already exists. Choose another number.'),
      findsOneWidget,
    );
  });

  testWidgets('edit: change a bed category and save', (tester) async {
    await seedRoom('5');
    await openRooms(tester);
    await tapKey(tester, 'rooms.edit.5');
    expect(find.text('Edit Room 5'), findsOneWidget);
    expect(
      find.text(
        'Changing a category affects new check-ins only. Guests '
        'already staying keep their price.',
      ),
      findsOneWidget,
    );

    await pick(tester, 'edit.bedB', 'VIP · KES 1,000');
    await tapKey(tester, 'edit.save');
    expect(find.text('Edit Room 5'), findsNothing);
    expect(find.text('B · VIP'), findsOneWidget);
    expect(await env.auditFor('bed.update'), hasLength(1));
  });

  testWidgets('a guest in bed B: deactivate is disabled with the reason', (
    tester,
  ) async {
    final room = await seedRoom('5');
    await env.checkIn(room.beds.last.id, by: owner);
    await openRooms(tester);
    await tapKey(tester, 'rooms.edit.5');

    final deactivate = tester.widget<TextButton>(
      find.byKey(const ValueKey('edit.deactivateB')),
    );
    expect(deactivate.onPressed, isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('edit.bedBlockerB')),
        matching: find.text(
          'Bed B has a guest right now. Check them out first.',
        ),
      ),
      findsOneWidget,
    );
    // The room can't close either, for the same reason.
    expect(find.byKey(const ValueKey('edit.roomBlocker')), findsOneWidget);
  });

  testWidgets('close a room for repairs, then reopen it', (tester) async {
    await seedRoom('5');
    await openRooms(tester);
    await tapKey(tester, 'rooms.edit.5');
    await tapKey(tester, 'edit.closeRoom');
    expect(find.text('CLOSED · REPAIRS'), findsWidgets);
    expect(find.text('1 room · 0 beds active · 1 room closed'), findsOneWidget);

    await tapKey(tester, 'edit.reopenRoom');
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(await env.auditFor('room.deactivate'), hasLength(1));
    expect(await env.auditFor('room.reactivate'), isNotEmpty);
  });

  testWidgets(
    'deactivate bed B, then reactivate it; add bed B to a 1-bed room',
    (tester) async {
      await seedRoom('5');
      await seedRoom('6', twoBeds: false);
      await openRooms(tester);

      await tapKey(tester, 'rooms.edit.5');
      await tapKey(tester, 'edit.deactivateB');
      expect(find.text('B · closed'), findsOneWidget);
      await tapKey(tester, 'edit.reactivateB');
      expect(find.text('B · Deluxe'), findsOneWidget);

      await tapKey(tester, 'edit.cancel');
      await tapKey(tester, 'rooms.edit.6');
      await pick(tester, 'edit.newBedCategory', 'Comfort · KES 600');
      await tapKey(tester, 'edit.addBed');
      expect(find.text('B · Comfort'), findsOneWidget);
    },
  );

  testWidgets('a receptionist cannot open Rooms & beds (AD-1)', (tester) async {
    await env.addReceptionist('desk');
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await enterKey(tester, 'shift.float', '500');
    await tapKey(tester, 'shift.submit');
    expect(find.text('Rooms & beds'), findsNothing);

    app.read(routerProvider).go(Routes.adminRooms);
    await tester.pumpAndSettle();
    expect(locationOf(app), Routes.home);
    expect(find.byType(RoomsScreen), findsNothing);
  });
}
