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

  /// v1 is frozen as of 16 Oct 2026 (`drift_schemas/…/drift_schema_v1.json`).
  /// For every schema change: bump this, change the tables, run
  /// `dart run drift_dev make-migrations`, add the generated step to
  /// [_upgrade], and fill `test/drift/app_database/migration_test.dart` with
  /// rows that must survive. New NOT NULL columns get a default or a
  /// backfill in their step. Never edit an applied migration (CLAUDE.md).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      await seedV1(this, deviceId: const Uuid().v4(), now: _clock.now());
    }),
    onUpgrade: _upgrade,
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // A new setting added since this file was made starts at its default.
      if (details.hadUpgrade) {
        await insertMissingSettings(this, now: _clock.now());
      }
    },
  );

  /// One generated step per version, in order (`database.steps.dart`, from
  /// `make-migrations`), e.g. `stepByStep(from1To2: (m, schema) async {…})`.
  /// There are none yet: v1 is the only version.
  Future<void> _upgrade(Migrator m, int from, int to) async {
    if (from > to) {
      throw StateError(
        'This database is v$from, made by a newer version of the app '
        '(this one knows up to v$to).',
      );
    }
    throw StateError('No migration step from v$from to v$to.');
  }

  Future<void>? _closing;

  /// Safe to call more than once: a test-database reset closes it before
  /// its provider does.
  @override
  Future<void> close() => _closing ??= super.close();

  /// This install's device id, stamped on every synced row it writes.
  Future<String> deviceId() async =>
      _deviceId ??= (await select(device).getSingle()).deviceId;
}
