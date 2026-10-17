import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/features/auth/presentation/idle_lock.dart';
import 'package:lodging_pos/features/guests/data/guests_repository.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/features/setup/data/prices_repository.dart';
import 'package:lodging_pos/features/setup/data/rooms_repository.dart';
import 'package:lodging_pos/features/setup/data/staff_repository.dart';
import 'package:lodging_pos/features/setup/domain/rooms.dart';
import 'package:lodging_pos/features/setup/presentation/widgets/room_table.dart';

import '../helpers/fixtures.dart';

/// Every restyled screen at the front-desk laptop's size (1366×768) with the
/// real fonts: any overflow is reported as an error and fails the test.
void main() {
  late TestEnv env;

  setUpAll(loadAppFonts);
  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  Future<void> expectCleanLayout(
    WidgetTester tester,
    ProviderContainer app,
    String route,
    String visibleText,
  ) async {
    await tester.pumpAndSettle();
    expect(locationOf(app), route);
    expect(find.text(visibleText), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(tester.view.physicalSize, deskSize);
  }

  Future<void> withOwner() async =>
      env.users.createFirstAdmin(testSetup).then((_) {});

  testWidgets('first-run setup', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await expectCleanLayout(tester, app, Routes.setup, 'Set up this lodging');
  });

  testWidgets('first-run setup with every field error', (tester) async {
    final app = await pumpDeskApp(tester, env);
    await tapKey(tester, 'setup.submit');
    await expectCleanLayout(
      tester,
      app,
      Routes.setup,
      'Enter the lodging name',
    );
  });

  testWidgets('sign in', (tester) async {
    await withOwner();
    final app = await pumpDeskApp(tester, env);
    await expectCleanLayout(tester, app, Routes.login, 'Sign in');
  });

  testWidgets('sign in with a wrong password', (tester) async {
    await withOwner();
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'wrong-pass');
    await expectCleanLayout(
      tester,
      app,
      Routes.login,
      'Wrong username or password. Try again.',
    );
  });

  testWidgets('lock screen after idle, shift kept', (tester) async {
    await withOwner();
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 1000);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    env.clock.advance(const Duration(minutes: 10));
    await app.read(idleLockProvider.notifier).check();
    await expectCleanLayout(
      tester,
      app,
      Routes.login,
      'Screen locked after 10 minutes idle',
    );
  });

  testWidgets('lock screen after Lock screen', (tester) async {
    await withOwner();
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await tapKey(tester, 'shell.lock');
    await expectCleanLayout(tester, app, Routes.login, 'Screen locked');
  });

  testWidgets('change password', (tester) async {
    await withOwner();
    await env.addReceptionist('fresh', mustChangePassword: true);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'fresh', 'desk-pass');
    await expectCleanLayout(
      tester,
      app,
      Routes.changePassword,
      'Choose a new password',
    );
  });

  testWidgets('open shift, with an error', (tester) async {
    await withOwner();
    await env.addReceptionist('desk');
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.submit');
    await expectCleanLayout(
      tester,
      app,
      Routes.shift,
      'Enter the opening cash float',
    );
  });

  testWidgets('resume shift', (tester) async {
    await withOwner();
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 2000);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await expectCleanLayout(tester, app, Routes.shift, 'Continue my shift');
  });

  testWidgets('shift blocked by another receptionist', (tester) async {
    await withOwner();
    final desk = await env.addReceptionist('desk');
    await env.addReceptionist('tom');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 2000);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'tom', 'desk-pass');
    await expectCleanLayout(
      tester,
      app,
      Routes.shift,
      "Desk's shift must be closed first",
    );
  });

  testWidgets('desk shell: owner', (tester) async {
    await withOwner();
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'owner', 'owner-pass');
    await expectCleanLayout(tester, app, Routes.home, 'Owner · admin');
  });

  testWidgets('desk shell: receptionist in a shift', (tester) async {
    await withOwner();
    final desk = await env.addReceptionist('desk');
    await ShiftRepository(
      env.db,
      env.audit,
    ).openShift(user: desk, openingFloat: 1000);
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await tapKey(tester, 'shift.continue');
    await expectCleanLayout(
      tester,
      app,
      Routes.home,
      'Receptionist · shift since 22:00',
    );
  });

  group('Rooms & beds (AD-2)', () {
    /// 12 rooms as on the artboard, a guest in Room 5 bed B, Room 13 closed.
    Future<void> seedTwelveRooms() async {
      final owner = (await env.users.findByUsername('owner'))!.account;
      final repo = RoomsRepository(env.db, env.audit);
      for (var n = 1; n <= 12; n++) {
        final room = await repo.createRoom(
          owner,
          NewRoom(
            number: '$n',
            floor: n <= 5 ? 'Ground' : 'First',
            notes: null,
            bedACategoryId: SeedIds.vip,
            bedBCategoryId: n.isEven || n == 5 ? SeedIds.deluxe : null,
          ),
        );
        if (n == 5) await env.checkIn(room.beds.last.id, by: owner);
      }
      final closed = await repo.createRoom(
        owner,
        const NewRoom(
          number: '13',
          floor: 'First',
          notes: null,
          bedACategoryId: SeedIds.normal,
          bedBCategoryId: SeedIds.comfort,
        ),
      );
      await repo.deactivateBed(owner, closed.beds.last.id);
      await repo.deactivateRoom(owner, closed.id);
    }

    Future<ProviderContainer> openRooms(WidgetTester tester) async {
      await withOwner();
      await seedTwelveRooms();
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'nav.${Routes.adminRooms}');
      return app;
    }

    testWidgets('table of 13 rooms', (tester) async {
      final app = await openRooms(tester);
      await expectCleanLayout(
        tester,
        app,
        Routes.adminRooms,
        '13 rooms · 19 beds active · 1 room closed',
      );
    });

    testWidgets('edit panel with guest blockers', (tester) async {
      final app = await openRooms(tester);
      await tapKey(tester, 'rooms.edit.5');
      await expectCleanLayout(
        tester,
        app,
        Routes.adminRooms,
        'Bed B has a guest right now. Check them out first.',
      );
    });

    testWidgets('edit panel for a closed room with a closed bed', (
      tester,
    ) async {
      final app = await openRooms(tester);
      // The table builds rows lazily; Room 13 is below the fold at 768px.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('rooms.edit.13')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(RoomTable),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tapKey(tester, 'rooms.edit.13');
      await expectCleanLayout(tester, app, Routes.adminRooms, 'Reopen room');
    });

    testWidgets('add panel with two beds', (tester) async {
      final app = await openRooms(tester);
      await tapKey(tester, 'rooms.add');
      await tapKey(tester, 'choice.2');
      await expectCleanLayout(tester, app, Routes.adminRooms, 'Bed B category');
    });
  });

  group('Prices & settings (AD-3)', () {
    Future<ProviderContainer> openPrices(WidgetTester tester) async {
      await withOwner();
      final owner = (await env.users.findByUsername('owner'))!.account;
      final prices = PricesRepository(env.db, env.audit);
      // Eight categories, one closed, some in use: a fuller table than seed.
      for (final (name, price) in [
        ('Family room', 1500),
        ('Dormitory', 300),
        ('Executive suite', 2500),
        ('Budget', 400),
      ]) {
        await prices.addCategory(owner, name: name, pricePerNight: price);
      }
      await prices.closeCategory(
        owner,
        (await prices.categories()).last.category.id,
      );
      await RoomsRepository(env.db, env.audit).createRoom(
        owner,
        const NewRoom(
          number: '3',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: SeedIds.vip,
        ),
      );
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'nav.${Routes.adminPrices}');
      return app;
    }

    testWidgets('prices and settings', (tester) async {
      final app = await openPrices(tester);
      await expectCleanLayout(tester, app, Routes.adminPrices, 'Save prices');
    });

    testWidgets('edits, errors and the add row', (tester) async {
      final app = await openPrices(tester);
      await enterKey(tester, 'price.${SeedIds.deluxe}', '750');
      await enterKey(tester, 'price.${SeedIds.vip}', '250000');
      await tapKey(tester, 'prices.save');
      await tapKey(tester, 'categories.add');
      await enterKey(tester, 'settings.grace', '999');
      await enterKey(tester, 'settings.idleLock', '0');
      await enterKey(tester, 'settings.lodgingName', '');
      await tapKey(tester, 'settings.save');
      await expectCleanLayout(
        tester,
        app,
        Routes.adminPrices,
        'The price can be at most KES 100,000.',
      );
    });

    testWidgets('the confirmation dialog', (tester) async {
      final app = await openPrices(tester);
      for (final id in [SeedIds.vip, SeedIds.deluxe, SeedIds.comfort]) {
        await enterKey(tester, 'price.$id', '12500');
      }
      await tapKey(tester, 'prices.save');
      await expectCleanLayout(tester, app, Routes.adminPrices, 'Confirm');
    });
  });

  group('Users & staff (AD-4)', () {
    Future<(ProviderContainer, String)> openStaff(WidgetTester tester) async {
      await withOwner();
      final owner = (await env.users.findByUsername('owner'))!.account;
      final staff = StaffRepository(env.db, env.audit, env.hasher);
      final mary = await env.addReceptionist('mary');
      await ShiftRepository(
        env.db,
        env.audit,
      ).openShift(user: mary, openingFloat: 500);
      await env.addReceptionist('james', mustChangePassword: true);
      final kevin = await env.addReceptionist('kevin');
      await staff.disableUser(owner, kevin.id);
      final rose = await staff.addHousekeeper(
        owner,
        name: 'Rose Akinyi Wanjiru',
        phone: '0722123310',
      );
      await staff.addHousekeeper(owner, name: 'John Mutua', phone: '');
      final old = await staff.addHousekeeper(
        owner,
        name: 'Esther Njeri',
        phone: '0110234567',
      );
      await staff.deactivateHousekeeper(owner, old.id);
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'nav.${Routes.adminStaff}');
      return (app, rose.id);
    }

    testWidgets('users and housekeepers', (tester) async {
      final (app, _) = await openStaff(tester);
      await expectCleanLayout(
        tester,
        app,
        Routes.adminStaff,
        'Add receptionist',
      );
    });

    testWidgets('form errors and a housekeeper being edited', (tester) async {
      final (app, roseId) = await openStaff(tester);
      await enterKey(tester, 'addUser.username', 'x');
      await enterKey(tester, 'addUser.password', 'short');
      await tapKey(tester, 'addUser.save');
      await tapKey(tester, 'hk.edit.$roseId');
      await enterKey(tester, 'hk.editPhone', '123');
      await tapKey(tester, 'hk.save');
      await expectCleanLayout(tester, app, Routes.adminStaff, 'Deactivate');
    });

    testWidgets('the disable warning dialog', (tester) async {
      final (app, _) = await openStaff(tester);
      await tapKey(tester, 'users.disable.mary');
      await expectCleanLayout(
        tester,
        app,
        Routes.adminStaff,
        'Disable Desk MARY?',
      );
    });
  });

  group('Guests (FD-3)', () {
    Future<ProviderContainer> openGuests(WidgetTester tester) async {
      await withOwner();
      final owner = (await env.users.findByUsername('owner'))!.account;
      final guests = GuestsRepository(env.db, env.audit);
      for (var i = 0; i < 9; i++) {
        await guests.register(
          owner,
          GuestForm(
            fullName: 'Guest With A Rather Long Full Name $i',
            phone: '07224189${i.toString().padLeft(2, '0')}',
            idType: i.isEven ? IdType.passport : IdType.nationalId,
            idNumber: i.isEven ? 'AK12345$i' : '1234567$i',
          ),
        );
      }
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'nav.${Routes.guests}');
      return app;
    }

    testWidgets('empty search', (tester) async {
      final app = await openGuests(tester);
      await expectCleanLayout(
        tester,
        app,
        Routes.guests,
        'Find by phone or ID number',
      );
    });

    testWidgets('8 matches, one opened, correcting with errors', (
      tester,
    ) async {
      final app = await openGuests(tester);
      await enterKey(tester, 'guests.search', '0722');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Long Full Name 1').first);
      await tester.pumpAndSettle();
      await tapKey(tester, 'correct.open');
      await enterKey(tester, 'correct.phone', '12');
      await enterKey(tester, 'correct.idNumber', 'x');
      await tapKey(tester, 'correct.save');
      await expectCleanLayout(tester, app, Routes.guests, 'Save changes');
    });

    testWidgets('registering with errors and a shared-phone notice', (
      tester,
    ) async {
      final app = await openGuests(tester);
      await tapKey(tester, 'guests.register');
      await enterKey(tester, 'newGuest.phone', '0722418900');
      await enterKey(tester, 'newGuest.idNumber', '123');
      await tapKey(tester, 'newGuest.save');
      await expectCleanLayout(tester, app, Routes.guests, 'Register guest');
    });
  });

  group('Bed board (FD-2)', () {
    /// 12 rooms as on the artboard: 6 with one bed, 6 with two (18 beds),
    /// some in use, some to clean; with [overstay], Room 5 B overstays.
    Future<ProviderContainer> openBoard(
      WidgetTester tester, {
      required bool overstay,
    }) async {
      await withOwner();
      final owner = (await env.users.findByUsername('owner'))!.account;
      final repo = RoomsRepository(env.db, env.audit);
      final created = <String, RoomSummary>{};
      for (var n = 1; n <= 12; n++) {
        final twoBeds = const {2, 3, 5, 7, 8, 11}.contains(n);
        created['$n'] = await repo.createRoom(
          owner,
          NewRoom(
            number: '$n',
            floor: null,
            notes: null,
            bedACategoryId: n.isEven ? SeedIds.deluxe : SeedIds.comfort,
            bedBCategoryId: twoBeds ? SeedIds.normal : null,
          ),
        );
      }
      if (overstay) {
        // Yesterday's 1-night stay: paid to 10:00 today, long past grace.
        env.clock.set(env.clock.now().subtract(const Duration(days: 2)));
        await env.checkIn(created['5']!.beds.last.id, by: owner);
        env.clock.set(env.clock.now().add(const Duration(days: 2)));
      }
      for (final n in ['2', '3', '6', '8', '9']) {
        await env.checkIn(created[n]!.beds.first.id, by: owner, nights: 3);
      }
      final gone = await env.checkIn(created['4']!.beds.first.id, by: owner);
      await env.checkOut(gone, by: owner);
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      return app;
    }

    double gridOverflow(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('board.grid')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .maxScrollExtent;

    testWidgets('12 rooms, no overstay: everything fits without scrolling', (
      tester,
    ) async {
      final app = await openBoard(tester, overstay: false);
      await expectCleanLayout(tester, app, Routes.home, 'Bed board');
      expect(find.byKey(const ValueKey('board.overstayBar')), findsNothing);
      expect(find.byKey(const ValueKey('board.room.12')), findsOneWidget);
      expect(gridOverflow(tester), 0);
    });

    testWidgets('12 rooms with the overstay bar: no overflow', (tester) async {
      final app = await openBoard(tester, overstay: true);
      await expectCleanLayout(tester, app, Routes.home, 'Bed board');
      expect(find.byKey(const ValueKey('board.overstayBar')), findsOneWidget);
    });
  });
}
