import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/app.dart';
import 'package:lodging_pos/app/router.dart';
import 'package:lodging_pos/core/audit/audit_writer.dart';
import 'package:lodging_pos/core/auth/password_hasher.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/database_provider.dart';
import 'package:lodging_pos/features/auth/data/user_repository.dart';
import 'package:lodging_pos/features/auth/domain/setup.dart';
import 'package:lodging_pos/features/auth/presentation/idle_lock.dart';

/// 22:00 Nairobi, 14 Oct 2026.
final testT0 = DateTime.utc(2026, 10, 14, 19);

const testSetup = SetupInput(
  fullName: 'Grace Owner',
  username: 'Owner',
  password: 'owner-pass',
  confirmPassword: 'owner-pass',
  lodgingName: 'Sunrise Lodge',
);

/// An in-memory database with the real writer and a fast hasher.
class TestEnv {
  TestEnv() : clock = FixedClock(testT0) {
    db = AppDatabase(NativeDatabase.memory(), clock: clock);
    audit = AuditWriter(db, clock);
    users = UserRepository(db, audit, hasher);
  }

  final FixedClock clock;
  final hasher = const PasswordHasher.fast();
  late final AppDatabase db;
  late final AuditWriter audit;
  late final UserRepository users;

  Future<void> close() => db.close();

  /// Provider overrides that run the real app against this environment.
  /// The idle-lock timer is off; tests call `IdleLock.check()` themselves.
  List<Override> get overrides => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    passwordHasherProvider.overrideWithValue(hasher),
    idleCheckIntervalProvider.overrideWithValue(null),
  ];

  /// Until AD-4 adds user management, tests create receptionists directly
  /// through the writer.
  Future<UserAccount> addReceptionist(
    String username, {
    String password = 'desk-pass',
    bool mustChangePassword = false,
    bool isActive = true,
  }) async {
    final hash = await hasher.hash(password);
    final row = await audit.writeWithAudit(
      action: 'user.create',
      userId: null,
      body: (w) => w.insert(
        db.users,
        UsersCompanion.insert(
          fullName: 'Desk ${username.toUpperCase()}',
          username: username,
          passwordHash: hash,
          role: Role.receptionist.name,
          mustChangePassword: mustChangePassword,
          isActive: Value(isActive),
        ),
      ),
    );
    return UserAccount(
      id: row.id,
      fullName: row.fullName,
      username: row.username,
      role: Role.receptionist,
      isActive: row.isActive,
      mustChangePassword: row.mustChangePassword,
    );
  }

  /// Test-only stand-in for FD-4 check-in, until it exists: writes a
  /// guest, an active stay on [bedId] for [blocks] blocks at [pricePerBlock],
  /// a cash payment and its charge, through the writer. Opens a shift for
  /// [by] if this device has none. Returns the stay id.
  Future<String> checkIn(
    String bedId, {
    required UserAccount by,
    int blocks = 1,
    int pricePerBlock = 700,
  }) {
    final now = clock.now();
    final paidUntil = now.add(Duration(hours: 12 * blocks));
    return audit.writeWithAudit(
      action: 'stay.check_in',
      userId: by.id,
      body: (w) async {
        final open = await (db.select(
          db.shifts,
        )..where((s) => s.status.equals('open'))).getSingleOrNull();
        final shiftId =
            open?.id ??
            (await w.insert(
              db.shifts,
              ShiftsCompanion.insert(
                userId: by.id,
                openedAt: now,
                openingFloat: 0,
                status: 'open',
              ),
              action: 'shift.open',
            )).id;
        final guest = await w.insert(
          db.guests,
          GuestsCompanion.insert(fullName: 'Test Guest', phone: '0700000000'),
        );
        final stay = await w.insert(
          db.stays,
          StaysCompanion.insert(
            guestId: guest.id,
            bedId: bedId,
            checkInAt: now,
            paidUntil: paidUntil,
            status: 'active',
            checkedInBy: by.id,
          ),
        );
        final payment = await w.insert(
          db.payments,
          PaymentsCompanion.insert(
            receiptNumber: 'T-${stay.id.substring(0, 8)}',
            shiftId: shiftId,
            receivedBy: by.id,
            receivedAt: now,
            amount: blocks * pricePerBlock,
            method: 'cash',
          ),
        );
        await w.insert(
          db.stayCharges,
          StayChargesCompanion.insert(
            stayId: stay.id,
            paymentId: payment.id,
            kind: 'check_in',
            blocks: blocks,
            pricePerBlock: pricePerBlock,
            amount: blocks * pricePerBlock,
            periodStart: now,
            periodEnd: paidUntil,
          ),
        );
        return stay.id;
      },
    );
  }

  /// Test-only stand-in for FD-8 checkout.
  Future<void> checkOut(String stayId, {required UserAccount by}) =>
      audit.writeWithAudit(
        action: 'stay.check_out',
        userId: by.id,
        body: (w) => w.update(
          db.stays,
          stayId,
          StaysCompanion(
            status: const Value('closed'),
            checkedOutAt: Value(clock.now()),
            checkedOutBy: Value(by.id),
          ),
        ),
      );

  Future<List<AuditLogRow>> auditFor(String action) =>
      (db.select(db.auditLog)..where((a) => a.action.equals(action))).get();
}

/// The front-desk laptop: 1366×768 at 1:1.
const deskSize = Size(1366, 768);

/// Runs the real app on [env] at the desk's screen size.
Future<ProviderContainer> pumpDeskApp(WidgetTester tester, TestEnv env) async {
  tester.view
    ..physicalSize = deskSize
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: env.overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Scrolls the widget with [key] into view, then taps it.
Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enterKey(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
}

Future<void> signInAs(
  WidgetTester tester,
  String username,
  String password,
) async {
  await enterKey(tester, 'login.username', username);
  await enterKey(tester, 'login.password', password);
  await tapKey(tester, 'login.submit');
}

String locationOf(ProviderContainer app) =>
    app.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

/// Loads the bundled fonts so layout tests measure real text widths
/// (by default, widget tests use a wide placeholder font).
Future<void> loadAppFonts() async {
  const families = {
    'Manrope': [
      'assets/fonts/manrope/manrope-medium.ttf',
      'assets/fonts/manrope/manrope-semibold.ttf',
      'assets/fonts/manrope/manrope-bold.ttf',
      'assets/fonts/manrope/manrope-extrabold.ttf',
    ],
    'IBMPlexMono': [
      'assets/fonts/ibm_plex_mono/IBMPlexMono-Medium.ttf',
      'assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf',
    ],
  };
  for (final MapEntry(key: family, value: files) in families.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load(file));
    }
    await loader.load();
  }
}
