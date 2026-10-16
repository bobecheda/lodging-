import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../clock/clock.dart';
import 'seed.dart';
import 'tables/admin_tables.dart';
import 'tables/desk_tables.dart';
import 'tables/setup_tables.dart';
import 'tables/system_tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    // Setup (admin owns)
    Users,
    Settings,
    BedCategories,
    Rooms,
    Beds,
    Housekeepers,
    // Front desk (desk owns)
    Guests,
    Shifts,
    Stays,
    Payments,
    StayCharges,
    Refunds,
    HousekeepingTasks,
    InventoryMovements,
    // Admin-owned records
    Voids,
    RefundDecisions,
    Expenses,
    InventoryItems,
    // System
    AuditLog,
    Outbox,
    Device,
    ReceiptCounter,
  ],
  include: {'triggers.drift'},
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor, {required this._clock});

  final Clock _clock;
  String? _deviceId;

  /// Bump for every schema change and add a step to `onUpgrade`; never edit
  /// an applied migration. After bumping, run
  /// `dart run drift_dev make-migrations` to snapshot the new version and
  /// regenerate the migration tests.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      await seedV1(this, deviceId: const Uuid().v4(), now: _clock.now());
    }),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// This install's device id, stamped on every synced row it writes.
  Future<String> deviceId() async =>
      _deviceId ??= (await select(device).getSingle()).deviceId;
}
