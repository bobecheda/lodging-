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
import 'package:lodging_pos/core/clock/clock_time.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/database_provider.dart';
import 'package:lodging_pos/features/auth/data/user_repository.dart';
import 'package:lodging_pos/features/auth/domain/setup.dart';
import 'package:lodging_pos/features/auth/presentation/idle_lock.dart';
import 'package:lodging_pos/features/backup/presentation/backup_providers.dart';
import 'package:lodging_pos/features/bed_board/presentation/bed_board_providers.dart';
import 'package:lodging_pos/features/guests/data/guests_repository.dart';
import 'package:lodging_pos/features/receipts/presentation/receipts_providers.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';
import 'package:lodging_pos/features/payments/domain/payment_rules.dart';
import 'package:lodging_pos/features/shifts/data/shift_repository.dart';
import 'package:lodging_pos/features/stays/data/check_in_repository.dart';
import 'package:lodging_pos/features/stays/data/check_out_repository.dart';
import 'package:lodging_pos/features/stays/domain/check_out.dart';
import 'package:lodging_pos/features/stays/domain/check_in.dart';
import 'package:lodging_pos/features/stays/domain/stay_rules.dart';

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

  /// The bed board's clock tick; null (no timer) unless a test sets it.
  Duration? boardTick;

  /// Stands in for the print dialog and the Documents folder.
  final receiptOutput = FakeReceiptOutput();

  /// The main backup folder (a temporary one), or null: no backups, as on
  /// web. Set it before pumping the app.
  String? backupFolder;

  /// The backup check's interval; null (no timer) unless a test sets it.
  Duration? backupCheck;

  /// Stands in for the folder picker and Explorer.
  final backupShell = FakeBackupShell();

  /// Provider overrides that run the real app against this environment.
  /// The idle-lock timer, the bed board's clock tick and the hourly backup
  /// check are off; tests call `IdleLock.check()`, set the clock or call
  /// `Backups.checkNow()` themselves.
  List<Override> get overrides => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock),
    passwordHasherProvider.overrideWithValue(hasher),
    idleCheckIntervalProvider.overrideWithValue(null),
    boardTickIntervalProvider.overrideWithValue(boardTick),
    receiptOutputProvider.overrideWithValue(receiptOutput),
    backupFolderProvider.overrideWithValue(switch (backupFolder) {
      final folder? => () async => folder,
      null => null,
    }),
    backupCheckIntervalProvider.overrideWithValue(backupCheck),
    backupShellProvider.overrideWithValue(backupShell),
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

  late final guests = GuestsRepository(db, audit);
  late final checkIns = CheckInRepository(db, audit, guests);

  /// Checks a new "Test Guest" (0700000000) into [bedId] for [nights], paid
  /// in cash, through the real check-in (FD-4) at the bed's category price.
  /// Opens a shift for [by] first if this device has none. Returns the stay
  /// id.
  ///
  /// Inside `tester.runAsync` with the app running, open the shift before
  /// pumping the app: opening it here is a write that wakes the app's
  /// watched queries in fake time, and the reads after it then wait forever
  /// for the database lock.
  Future<String> checkIn(
    String bedId, {
    required UserAccount by,
    int nights = 1,
  }) async {
    final shifts = ShiftRepository(db, audit);
    if (await shifts.openShiftOnThisDevice() == null) {
      await shifts.openShift(user: by, openingFloat: 0);
    }
    final row = await (db.select(db.beds).join([
      innerJoin(
        db.bedCategories,
        db.bedCategories.id.equalsExp(db.beds.categoryId),
      ),
    ])..where(db.beds.id.equals(bedId))).getSingle();
    final category = row.readTable(db.bedCategories);
    const phone = '0700000000';
    final result = await checkIns.checkIn(
      by,
      CheckInRequest(
        guest: NewGuest(
          const GuestForm(
            fullName: 'Test Guest',
            phone: phone,
            idType: null,
            idNumber: '',
          ),
          phoneSharedWith: {
            for (final g in await guests.withPhone(phone)) g.id,
          },
        ),
        method: PaymentMethod.cash,
        mpesaCode: null,
        shown: quoteCheckIn(
          checkInAt: clock.now(),
          nights: nights,
          checkout: const ClockTime(10, 0),
          beds: [
            LetBed(
              bedId: bedId,
              categoryId: category.id,
              categoryName: category.name,
              pricePerNight: category.pricePerNight,
            ),
          ],
        ),
      ),
    );
    return result.stayIds.single;
  }

  late final checkOuts = CheckOutRepository(db, audit);

  /// Checks [stayId] out now through the real checkout (FD-8): free, with a
  /// refund request, or with a late charge paid in cash, whichever applies.
  /// The bed is left `not_cleaned` (BR-9). [by] needs an open shift.
  Future<CheckOutResult> checkOut(
    String stayId, {
    required UserAccount by,
  }) async {
    final detail = await checkOuts.stay(stayId);
    final terms = checkoutTerms(
      detail.stay,
      clock.now(),
      await checkOuts.graceMinutes(),
    );
    return checkOuts.checkOut(
      by,
      CheckOutRequest(
        stayId: stayId,
        shown: terms,
        method: terms is LateCheckout ? PaymentMethod.cash : null,
      ),
    );
  }

  Future<List<AuditLogRow>> auditFor(String action) =>
      (db.select(db.auditLog)..where((a) => a.action.equals(action))).get();
}

/// The front-desk laptop: 1366×768 at 1:1.
const deskSize = Size(1366, 768);

/// Runs the real app on [env] at the desk's screen size, with any
/// [extraOverrides] on top.
Future<ProviderContainer> pumpDeskApp(
  WidgetTester tester,
  TestEnv env, {
  List<Override> extraOverrides = const [],
}) async {
  tester.view
    ..physicalSize = deskSize
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [...env.overrides, ...extraOverrides],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Lets work that does real file I/O (backups) finish: fake time never
/// completes it, so real time passes and the app pumps, in turns, until
/// [done].
Future<void> settleRealIo(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'the file work never finished');
  await tester.pumpAndSettle();
}

/// Scrolls the widget with [key] into view, then taps it.
Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Taps [key] inside [scope], where the same key appears more than once
/// on screen (e.g. the Extend card's and the checkout's Cash / M-Pesa).
Future<void> tapKeyIn(WidgetTester tester, String scope, String key) async {
  final finder = find.descendant(
    of: find.byKey(ValueKey(scope)),
    matching: find.byKey(ValueKey(key)),
  );
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

/// Answers the folder picker with [pick] (null: cancelled) and records
/// folders opened in Explorer.
class FakeBackupShell implements BackupShell {
  String? pick;
  final opened = <String>[];

  @override
  Future<String?> pickFolder() async => pick;

  @override
  Future<void> openFolder(String path) async => opened.add(path);
}

/// Records what would have been printed or saved. [printResult] false acts
/// like a cancelled print dialog.
class FakeReceiptOutput implements ReceiptOutput {
  bool printResult = true;
  final printed = <String>[];
  final saved = <String>[];
  final opened = <String>[];
  Uint8List? lastPdf;

  @override
  Future<bool> print(Uint8List pdf, {required String name}) async {
    lastPdf = pdf;
    if (printResult) printed.add(name);
    return printResult;
  }

  @override
  Future<String> save(
    Uint8List pdf, {
    required String folder,
    required String file,
  }) async {
    lastPdf = pdf;
    const documents = r'C:\Users\Desk\Documents';
    final path = [documents, folder, file].join(r'\');
    saved.add(path);
    return path;
  }

  @override
  Future<void> openFolder(String path) async => opened.add(path);
}
