import 'package:drift/drift.dart';
import 'package:drift/internal/versioned_schema.dart';
import 'package:uuid/uuid.dart';

import '../clock/clock.dart';
import 'database.steps.dart';
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
  AppDatabase(super.executor, {required this._clock, this._beforeMigration});

  final Clock _clock;

  /// Runs once before any migration, with the version the file is at: the
  /// app copies the file aside (`<file>.v1.bak`). Null for in-memory
  /// databases.
  final BeforeMigration? _beforeMigration;
  String? _deviceId;

  /// v1 is frozen as of 16 Oct 2026; v2 (FD-4) adds the category to each
  /// stay charge, v3 (FD-6) the room and bed to each stay, v4 (FD-9) task
  /// cancelling. Snapshots: `drift_schemas/app_database/`.
  /// For every schema change: bump this, change the tables, run
  /// `dart run drift_dev make-migrations`, add the generated step to
  /// [_steps], and fill `test/drift/app_database/migration_test.dart` with
  /// rows that must survive. New NOT NULL columns get a default or a
  /// backfill in their step. Never edit an applied migration (CLAUDE.md).
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      await seedV1(this, deviceId: const Uuid().v4(), now: _clock.now());
    }),
    onUpgrade: _upgrade,
    beforeOpen: (details) async {
      await _configureConnection();
      await customStatement('PRAGMA foreign_keys = ON');
      // A new setting added since this file was made starts at its default.
      if (details.hadUpgrade) {
        await insertMissingSettings(this, now: _clock.now());
      }
    },
  );

  /// Every upgrade, in one transaction: the generated steps in order
  /// ([_steps], from `make-migrations`), then a foreign key check over the
  /// whole file, then the new version number. If any of it fails, nothing
  /// changes and the file stays at its old version.
  ///
  /// Foreign keys are off while the steps run, so a step may rebuild a table
  /// (`alterTable`) that other rows point to; the pragma only works outside a
  /// transaction. `beforeOpen` turns them back on.
  Future<void> _upgrade(Migrator m, int from, int to) async {
    if (from > to) {
      throw StateError(
        'This database is v$from, made by a newer version of the app '
        '(this one knows up to v$to).',
      );
    }
    await _configureConnection();
    await _beforeMigration?.call(this, from);
    await customStatement('PRAGMA foreign_keys = OFF');
    await transaction(() async {
      await VersionedSchema.runMigrationSteps(
        migrator: m,
        from: from,
        to: to,
        steps: _steps,
      );
      final broken = await customSelect('PRAGMA foreign_key_check').get();
      if (broken.isNotEmpty) {
        throw MigrationFailed(from, to, [
          for (final row in broken)
            '${row.data['table']} row ${row.data['rowid']} → '
                '${row.data['parent']}',
        ]);
      }
      // Inside the transaction, so the version moves with the data.
      await customStatement('PRAGMA user_version = $to');
    });
  }

  /// WAL journal with `synchronous = FULL`: every commit is synced to disk
  /// before it returns, so a power cut can't lose a committed payment (WAL
  /// alone, at its usual NORMAL, may drop the last commits). Runs before a
  /// migration and on every open, outside any transaction (journal_mode
  /// can't change inside one). An in-memory database stays in `memory`
  /// journal mode; `synchronous` still applies.
  Future<void> _configureConnection() async {
    await customStatement('PRAGMA journal_mode = WAL');
    await customStatement('PRAGMA synchronous = FULL');
  }

  /// One step per version (`database.steps.dart`). Never edit a step once
  /// it has shipped; add the next one.
  static final _steps = migrationSteps(
    // v2 (FD-4): each charge keeps its bed's category, id and name, as at
    // check-in. Rebuilding the table fills both for existing rows from the
    // stay's bed (an UPDATE would trip the charges' triggers).
    from1To2: (m, schema) async {
      final charges = schema.stayCharges;
      CustomExpression<String> fromBed(String column) => CustomExpression(
        '(SELECT bed_categories.$column FROM stays '
        'JOIN beds ON beds.id = stays.bed_id '
        'JOIN bed_categories ON bed_categories.id = beds.category_id '
        'WHERE stays.id = stay_charges.stay_id)',
      );
      await m.alterTable(
        TableMigration(
          charges,
          newColumns: [charges.categoryId, charges.categoryName],
          columnTransformer: {
            charges.categoryId: fromBed('id'),
            charges.categoryName: fromBed('name'),
          },
        ),
      );
    },
    // v3 (FD-6): each stay keeps its room number and bed label as at
    // check-in, filled for existing stays from their bed and room.
    from2To3: (m, schema) async {
      final stays = schema.stays;
      await m.alterTable(
        TableMigration(
          stays,
          newColumns: [stays.roomNumber, stays.bedLabel],
          columnTransformer: {
            stays.roomNumber: const CustomExpression<String>(
              '(SELECT rooms.room_number FROM beds '
              'JOIN rooms ON rooms.id = beds.room_id '
              'WHERE beds.id = stays.bed_id)',
            ),
            stays.bedLabel: const CustomExpression<String>(
              '(SELECT beds.label FROM beds WHERE beds.id = stays.bed_id)',
            ),
          },
        ),
      );
    },
    // v4 (FD-9): a cleaning task can be cancelled (its bed or room closed).
    // Both new columns start empty: no task was cancelled before. The
    // rebuild puts back the old "one open task per bed" index, so it's
    // replaced with the new one that also leaves out cancelled tasks.
    from3To4: (m, schema) async {
      final tasks = schema.housekeepingTasks;
      await m.alterTable(
        TableMigration(
          tasks,
          newColumns: [tasks.cancelledAt, tasks.cancelledBy],
        ),
      );
      await m.drop(schema.housekeepingTasksOneOpenPerBed);
      await m.createIndex(schema.housekeepingTasksOneOpenPerBed);
    },
  );

  Future<void>? _closing;

  /// Safe to call more than once: a test-database reset closes it before
  /// its provider does.
  @override
  Future<void> close() => _closing ??= super.close();

  /// This install's device id, stamped on every synced row it writes.
  Future<String> deviceId() async =>
      _deviceId ??= (await select(device).getSingle()).deviceId;
}

/// Called with the open database and the version its file is at, before a
/// migration starts.
typedef BeforeMigration = Future<void> Function(AppDatabase db, int from);

/// A migration left foreign keys pointing nowhere, so it was rolled back
/// and the file kept its old version.
class MigrationFailed implements Exception {
  const MigrationFailed(this.from, this.to, this.problems);
  final int from;
  final int to;

  /// One line per broken foreign key: table, row and the table it points to.
  final List<String> problems;

  @override
  String toString() =>
      'The upgrade from v$from to v$to was undone: ${problems.length} broken '
      'foreign keys (${problems.join('; ')}).';
}
