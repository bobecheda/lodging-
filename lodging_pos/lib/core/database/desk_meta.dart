import 'package:drift/drift.dart';

import '../app_version.dart';
import 'database.dart';

/// This desk's own facts, kept in the local-only `sync_state` table (never
/// synced, never audited): the highest build that opened the file and the
/// folder the desk was installed in (story/desk-db-guards).
abstract final class DeskMetaKeys {
  static const build = 'desk.build';
  static const version = 'desk.version';
  static const installPath = 'desk.install_path';
}

Future<String?> _read(AppDatabase db, String key) async => (await (db.select(
  db.syncState,
)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

Future<void> _write(AppDatabase db, String key, String value) => db
    .into(db.syncState)
    .insertOnConflictUpdate(SyncStateCompanion.insert(key: key, value: value));

/// Raises the file's build stamp to [build]'s; never lowers it.
Future<void> raiseBuildStamp(AppDatabase db, AppBuild build) =>
    db.transaction(() async {
      final stored = int.tryParse(await _read(db, DeskMetaKeys.build) ?? '');
      if (stored != null && stored >= build.build) return;
      await _write(db, DeskMetaKeys.build, '${build.build}');
      await _write(db, DeskMetaKeys.version, build.version);
    });

/// The folder the desk was installed in, or null before it was recorded.
Future<String?> installPath(AppDatabase db) =>
    _read(db, DeskMetaKeys.installPath);

/// Records [path] as the desk's install folder.
Future<void> recordInstallPath(AppDatabase db, String path) =>
    _write(db, DeskMetaKeys.installPath, path);

/// Moves this device's receipt counter up to [floor] if it is lower (an
/// accepted restore; never down). Returns the next number before and after.
Future<(int, int)> raiseReceiptCounter(AppDatabase db, int floor) =>
    db.transaction(() async {
      final deviceId = await db.deviceId();
      final row = await (db.select(
        db.receiptCounter,
      )..where((c) => c.deviceId.equals(deviceId))).getSingle();
      final before = row.nextNumber;
      if (before >= floor) return (before, before);
      await (db.update(db.receiptCounter)
            ..where((c) => c.deviceId.equals(deviceId)))
          .write(ReceiptCounterCompanion(nextNumber: Value(floor)));
      return (before, floor);
    });
