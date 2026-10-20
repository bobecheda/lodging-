import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/auth/presentation/idle_lock.dart';
import 'package:lodging_pos/features/backup/data/backup_service.dart';
import 'package:lodging_pos/features/backup/domain/backup.dart';
import 'package:lodging_pos/features/backup/presentation/backup_providers.dart';
import 'package:lodging_pos/features/guests/data/guests_repository.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';

import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/settings/settings_repository.dart';
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
    /// [before] runs once the data is in, before the app starts.
    Future<ProviderContainer> openPrices(
      WidgetTester tester, {
      Future<void> Function(UserAccount owner)? before,
    }) async {
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
      await before?.call(owner);
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

    group('with the Backups card', () {
      late Directory temp;
      setUp(() {
        temp = Directory.systemTemp.createTempSync('lodging_layout');
        env.backupFolder = temp.path;
        env.clock.set(nairobiInstant(2026, 10, 20, 9));
      });
      tearDown(() => temp.deleteSync(recursive: true));

      /// A long second-folder path that isn't there (the USB drive out).
      Future<void> unpluggedSecondFolder(UserAccount owner) async {
        await BackupService(
          env.db,
          env.audit,
          env.clock,
          SettingsRepository(env.db),
          folder: temp.path,
        ).setSecondFolder(
          owner,
          r'E:\Sunrise Lodge backups\Front desk PC\Daily copies 2026',
        );
      }

      testWidgets('a backup with its second copy skipped', (tester) async {
        final app = await openPrices(tester, before: unpluggedSecondFolder);
        await settleRealIo(
          tester,
          () => app.read(backupsProvider).second is SecondSkipped,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('backups.second.note')),
        );
        await expectCleanLayout(
          tester,
          app,
          Routes.adminPrices,
          'Second copy skipped: USB drive not found. Main backup OK.',
        );
      });

      testWidgets('a failed backup: the sidebar chip and the reason', (
        tester,
      ) async {
        Directory(
          '${temp.path}${Platform.pathSeparator}'
          '${backupFileName(env.clock.now())}.partial',
        ).createSync();
        final app = await openPrices(tester, before: unpluggedSecondFolder);
        await settleRealIo(
          tester,
          () => app.read(backupsProvider).lastFailure != null,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('backups.failed')),
        );
        await expectCleanLayout(
          tester,
          app,
          Routes.adminPrices,
          'Backup failed · none yet',
        );
      });
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

  group('Check-in (FD-4)', () {
    /// The owner with a shift of their own, room 7 (A Deluxe, B Comfort)
    /// and a returning guest with a long name.
    Future<ProviderContainer> openCheckIn(
      WidgetTester tester, {
      bool shift = true,
      bool dirtyB = false,
      int extraRooms = 0,
    }) async {
      await withOwner();
      final owner = (await env.users.findByUsername('owner'))!.account;
      final repo = RoomsRepository(env.db, env.audit);
      if (shift) {
        await ShiftRepository(
          env.db,
          env.audit,
        ).openShift(user: owner, openingFloat: 0);
      }
      final r7 = await repo.createRoom(
        owner,
        const NewRoom(
          number: '7',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: SeedIds.comfort,
        ),
      );
      for (var n = 10; n < 10 + extraRooms; n++) {
        await repo.createRoom(
          owner,
          NewRoom(
            number: '$n',
            floor: null,
            notes: null,
            bedACategoryId: SeedIds.deluxe,
            bedBCategoryId: SeedIds.normal,
          ),
        );
      }
      if (dirtyB) {
        // Straight to not_cleaned, so no shift is opened on the way.
        await env.audit.writeWithAudit(
          action: 'bed.update',
          userId: owner.id,
          body: (w) => w.update(
            env.db.beds,
            r7.beds.last.id,
            const BedsCompanion(cleanliness: Value('not_cleaned')),
          ),
        );
      }
      await GuestsRepository(env.db, env.audit).register(
        owner,
        const GuestForm(
          fullName: 'Grace Wanjiru Achieng-Odhiambo',
          phone: '0722418905',
          idType: IdType.nationalId,
          idNumber: '12343921',
        ),
      );
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      return app;
    }

    Future<void> chooseGuest(WidgetTester tester) async {
      await enterKey(tester, 'guests.search', '0722');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grace Wanjiru Achieng-Odhiambo').first);
      await tester.pumpAndSettle();
    }

    testWidgets('one bed, returning guest, M-Pesa with a code error', (
      tester,
    ) async {
      final app = await openCheckIn(tester);
      await tapKey(tester, 'board.bed.7A');
      await chooseGuest(tester);
      await tapKey(tester, 'choice.PaymentMethod.paybill');
      await tapKey(tester, 'checkIn.save'); // no code yet
      await expectCleanLayout(tester, app, Routes.checkIn, 'New check-in');
      expect(find.text('Enter the M-Pesa code.'), findsOneWidget);
    });

    testWidgets('both beds, registering a new guest with errors and a '
        'shared-phone notice', (tester) async {
      final app = await openCheckIn(tester);
      await tapKey(tester, 'board.bed.7A');
      await tapKey(tester, 'checkIn.wholeRoom');
      await tapKey(tester, 'guests.register');
      await enterKey(tester, 'newGuest.phone', '0722 418 905');
      await enterKey(tester, 'newGuest.idNumber', '12');
      await tester.pumpAndSettle();
      await tapKey(tester, 'newGuest.save');
      await expectCleanLayout(tester, app, Routes.checkIn, 'New check-in');
      expect(
        find.byKey(const ValueKey('newGuest.sharedPhone')),
        findsOneWidget,
      );
      expect(find.text('Bed A · 1 × KES 700'), findsOneWidget);
    });

    testWidgets('no shift of their own, Bed B needs cleaning', (tester) async {
      final app = await openCheckIn(tester, shift: false, dirtyB: true);
      await tapKey(tester, 'board.bed.7A');
      await chooseGuest(tester);
      await expectCleanLayout(tester, app, Routes.checkIn, 'New check-in');
      expect(find.byKey(const ValueKey('checkIn.noShift')), findsOneWidget);
      expect(find.text('Bed B needs cleaning first'), findsOneWidget);
    });

    testWidgets('choosing from 25 Ready beds', (tester) async {
      final app = await openCheckIn(tester, extraRooms: 12);
      await tapKey(tester, 'board.newCheckIn');
      await expectCleanLayout(tester, app, Routes.checkIn, 'New check-in');
      expect(find.byKey(const ValueKey('checkIn.pick.7A')), findsOneWidget);
    });

    testWidgets('step 4: checked in', (tester) async {
      final app = await openCheckIn(tester);
      await tapKey(tester, 'board.bed.7A');
      await tapKey(tester, 'checkIn.wholeRoom');
      await chooseGuest(tester);
      await tapKey(tester, 'choice.PaymentMethod.cash');
      await tapKey(tester, 'checkIn.save');
      await expectCleanLayout(tester, app, Routes.checkIn, 'Checked in');
    });
  });

  group('Receipts (FD-6)', () {
    testWidgets('a list of receipts and a two-bed receipt, saved', (
      tester,
    ) async {
      await withOwner();
      final owner = (await env.users.findByUsername('owner'))!.account;
      await ShiftRepository(
        env.db,
        env.audit,
      ).openShift(user: owner, openingFloat: 0);
      final repo = RoomsRepository(env.db, env.audit);
      for (var n = 1; n <= 12; n++) {
        final room = await repo.createRoom(
          owner,
          NewRoom(
            number: '$n',
            floor: null,
            notes: null,
            bedACategoryId: SeedIds.deluxe,
            bedBCategoryId: SeedIds.comfort,
          ),
        );
        await env.checkIn(room.beds.first.id, by: owner, nights: n);
      }
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'nav.${Routes.receipts}');
      await tapKey(tester, 'receipts.item.R-000012');
      await tapKey(tester, 'receipt.save');
      await expectCleanLayout(tester, app, Routes.receipts, 'Receipts');
      expect(find.byKey(const ValueKey('receipt.saved')), findsOneWidget);
    });
  });

  group('Bed panel (FD-7, FD-8)', () {
    /// The owner with a shift, room 5 let for [nights] from Thu 19:00, the
    /// clock then set to [now]; the panel open.
    Future<ProviderContainer> openPanel(
      WidgetTester tester, {
      required int nights,
      required DateTime now,
      bool viaBar = false,
      bool viaExtend = false,
    }) async {
      await withOwner();
      final owner = (await env.users.findByUsername('owner'))!.account;
      env.clock.set(nairobiInstant(2026, 10, 15, 19));
      final room = await RoomsRepository(env.db, env.audit).createRoom(
        owner,
        const NewRoom(
          number: '5',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: SeedIds.comfort,
        ),
      );
      await env.checkIn(room.beds.first.id, by: owner, nights: nights);
      env.clock.set(now);
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(
        tester,
        viaExtend
            ? 'board.overstay.extend'
            : viaBar
            ? 'board.overstay.checkOut'
            : 'board.bed.5A',
      );
      return app;
    }

    testWidgets('early checkout with the refund figures', (tester) async {
      final app = await openPanel(
        tester,
        nights: 10,
        now: nairobiInstant(2026, 10, 21, 15),
      );
      await expectCleanLayout(tester, app, Routes.home, 'Room 5 · Bed A');
      expect(find.byKey(const ValueKey('panel.refund')), findsOneWidget);
    });

    testWidgets('late, from the overstay bar, with M-Pesa and an error', (
      tester,
    ) async {
      final app = await openPanel(
        tester,
        nights: 1,
        now: nairobiInstant(2026, 10, 17, 13),
        viaBar: true,
      );
      await tapKeyIn(tester, 'panel.method', 'choice.PaymentMethod.paybill');
      await tapKey(tester, 'panel.checkOut');
      await expectCleanLayout(tester, app, Routes.home, 'Room 5 · Bed A');
      expect(find.text('Enter the M-Pesa code.'), findsOneWidget);
      expect(find.byKey(const ValueKey('panel.overstay')), findsOneWidget);
    });

    testWidgets('after a late checkout: the receipt in the panel', (
      tester,
    ) async {
      final app = await openPanel(
        tester,
        nights: 1,
        now: nairobiInstant(2026, 10, 16, 11, 30),
      );
      await tapKeyIn(tester, 'panel.method', 'choice.PaymentMethod.cash');
      await tapKey(tester, 'panel.checkOut');
      await expectCleanLayout(tester, app, Routes.home, 'Late checkout');
      expect(find.byKey(const ValueKey('receipt.view')), findsOneWidget);
    });

    testWidgets('extend during an overstay: the minimum, its reason and a '
        'nights error (FD-7)', (tester) async {
      final app = await openPanel(
        tester,
        nights: 1,
        now: nairobiInstant(2026, 10, 18, 12),
        viaExtend: true,
      );
      await enterKey(tester, 'stepper.value', '1');
      await tester.pumpAndSettle();
      await tapKeyIn(tester, 'extend.method', 'choice.PaymentMethod.paybill');
      await expectCleanLayout(tester, app, Routes.home, 'Room 5 · Bed A');
      expect(find.byKey(const ValueKey('extend.minReason')), findsOneWidget);
      expect(find.byKey(const ValueKey('extend.nightsError')), findsOneWidget);
    });

    testWidgets('after an extension: the receipt in the panel (FD-7)', (
      tester,
    ) async {
      final app = await openPanel(
        tester,
        nights: 1,
        now: nairobiInstant(2026, 10, 16, 8),
      );
      await tapKey(tester, 'stepper.plus');
      await tapKeyIn(tester, 'extend.method', 'choice.PaymentMethod.cash');
      await tapKey(tester, 'extend.save');
      await expectCleanLayout(tester, app, Routes.home, 'Extended by 2 nights');
      expect(find.byKey(const ValueKey('receipt.view')), findsOneWidget);
    });
  });

  group('Cleaning panel (FD-9)', () {
    testWidgets('assign, then the assigned state with Reassign open', (
      tester,
    ) async {
      await withOwner();
      final owner = (await env.users.findByUsername('owner'))!.account;
      final room = await RoomsRepository(env.db, env.audit).createRoom(
        owner,
        const NewRoom(
          number: '7',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: SeedIds.comfort,
        ),
      );
      final staff = StaffRepository(env.db, env.audit, env.hasher);
      await staff.addHousekeeper(owner, name: 'Rose Akinyi', phone: '');
      await staff.addHousekeeper(owner, name: 'Rose Mutua', phone: '');
      final stay = await env.checkIn(room.beds.first.id, by: owner);
      await env.checkOut(stay, by: owner);
      final app = await pumpDeskApp(tester, env);
      await signInAs(tester, 'owner', 'owner-pass');
      await tapKey(tester, 'board.bed.7A');
      await tapKey(tester, 'cleaning.housekeeper');
      await tester.tap(find.text('Rose Akinyi').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'cleaning.assign');
      await tapKey(tester, 'cleaning.reassign');
      await expectCleanLayout(tester, app, Routes.home, 'Room 7 · Bed A');
      expect(
        find.byKey(const ValueKey('cleaning.reassignSave')),
        findsOneWidget,
      );
    });
  });

  group('Shift close (FD-11)', () {
    Future<(ProviderContainer, String)> withMaryShift(
      WidgetTester tester, {
      required String signIn,
    }) async {
      await withOwner();
      final owner = (await env.users.findByUsername('owner'))!.account;
      final mary = await env.addReceptionist('mary');
      final shift = await ShiftRepository(
        env.db,
        env.audit,
      ).openShift(user: mary, openingFloat: 1000);
      final room = await RoomsRepository(env.db, env.audit).createRoom(
        owner,
        const NewRoom(
          number: '7',
          floor: null,
          notes: null,
          bedACategoryId: SeedIds.deluxe,
          bedBCategoryId: null,
        ),
      );
      await env.checkIn(room.beds.single.id, by: mary, nights: 3);
      final app = await pumpDeskApp(tester, env);
      await signInAs(
        tester,
        signIn,
        signIn == 'owner' ? 'owner-pass' : 'desk-pass',
      );
      return (app, shift.id);
    }

    testWidgets('review after a recount, short, with the note error', (
      tester,
    ) async {
      final (app, _) = await withMaryShift(tester, signIn: 'mary');
      await tapKey(tester, 'shift.continue');
      await tapKey(tester, 'shell.closeShift');
      await enterKey(tester, 'closeShift.count', '2000');
      await tapKey(tester, 'closeShift.review');
      await tapKey(tester, 'closeShift.recount');
      await enterKey(tester, 'closeShift.count', '2900');
      await tapKey(tester, 'closeShift.review');
      await tapKey(tester, 'closeShift.confirm');
      await expectCleanLayout(tester, app, Routes.closeShift, 'Close shift');
      expect(find.text('Say why the cash is short.'), findsOneWidget);
    });

    testWidgets('the owner’s Shifts: a closed shift with a high variance, '
        'a recount and who closed it', (tester) async {
      final (app, shiftId) = await withMaryShift(tester, signIn: 'owner');
      final owner = (await env.users.findByUsername('owner'))!.account;
      final shifts = ShiftRepository(env.db, env.audit);
      await tester.runAsync(
        () async => shifts.closeShift(
          owner,
          shiftId,
          firstCount: 2600,
          counted: 2800,
          note: 'Change for a large note was given from the float twice',
          shown: await shifts.takings(shiftId),
        ),
      );
      await tapKey(tester, 'nav.${Routes.shifts}');
      await expectCleanLayout(tester, app, Routes.shifts, 'Shifts');
      expect(find.byKey(ValueKey('shifts.recount.$shiftId')), findsOneWidget);
      expect(find.byKey(ValueKey('shifts.closedBy.$shiftId')), findsOneWidget);
    });
  });
}
