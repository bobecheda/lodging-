import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import '../app_version.dart';
import '../clock/nairobi.dart';
import 'database_provider.dart';
import 'desk_meta.dart';
import 'desk_startup.dart';

// The one place for work on the live database file and the files beside
// it: `lodging_pos.sqlite` (and its -wal, -shm, -journal), the
// pre-upgrade copies, the high-water mark and the lock
// (story/desk-db-guards). `test/policy/live_file_ops_test.dart` fails the
// build if anything else renames, copies or deletes them.

/// A fresh in-memory database, to compare a file's schema against.
QueryExecutor? inMemoryExecutor() => NativeDatabase.memory();

const databaseFileName = '$databaseName.sqlite';
const markFileName = '$databaseName.mark.json';
const lockFileName = '$databaseName.lock';

String _join(String folder, String name) =>
    '$folder${Platform.pathSeparator}$name';

/// `<app support dir>`: the database, its backups and everything beside it.
Future<String> dataFolder() async =>
    (await getApplicationSupportDirectory()).path;

/// `<app support dir>/lodging_pos.sqlite`.
Future<String> databaseFilePath() async =>
    _join(await dataFolder(), databaseFileName);

// ── The startup checks ──────────────────────────────────────────────────

/// Locks the data folder, reads it and judges whether the app may open the
/// database (docs/backup-restore.md, "Startup checks"). Runs before the
/// database is opened; nothing here writes to it.
Future<DeskStartup> runDeskStartup({
  required AppBuild build,
  required int schemaVersion,
  required bool checkLocation,
}) async {
  final folder = await dataFolder();
  final exe = Platform.resolvedExecutable;
  final holder = lockDataFolder(
    folder,
    LockHolder(
      exePath: exe,
      version: build.label,
      since: DateTime.now().toUtc().toIso8601String(),
    ),
  );
  final inspection = await inspectDataFolder(folder, heldBy: holder);
  final verdict = judgeStartup(
    inspection,
    build: build,
    schemaVersion: schemaVersion,
  );
  final exeFolder = File(exe).parent.path;
  return DeskStartup(
    folder: folder,
    verdict: verdict,
    inspection: inspection,
    location: checkLocation
        ? judgeLocation(
            exeFolder: exeFolder,
            removable: isRemovableDrive(exeFolder),
            recorded: inspection.live?.installPath,
          )
        : const LocationOk(),
  );
}

// ── The lock ────────────────────────────────────────────────────────────

/// The locked byte, far past the holder's details at the start of the
/// file, so a second copy can still read who holds it.
const lockByteOffset = 1 << 20;

RandomAccessFile? _held;

/// Takes the data folder's lock for this process, writing [me] into the
/// lock file; returns null when taken (or already held by this process),
/// or the copy that holds it. Windows releases the lock when the process
/// ends, even after a crash.
LockHolder? lockDataFolder(String folder, LockHolder me) {
  if (_held != null) return null;
  Directory(folder).createSync(recursive: true);
  final path = _join(folder, lockFileName);
  final file = File(path).openSync(mode: FileMode.append);
  try {
    file.lockSync(FileLock.exclusive, lockByteOffset, lockByteOffset + 1);
  } on FileSystemException {
    file.closeSync();
    try {
      return LockHolder.fromJson(
        (jsonDecode(File(path).readAsStringSync()) as Map)
            .cast<String, Object?>(),
      );
    } on Object {
      return const LockHolder(
        exePath: 'unknown',
        version: 'unknown',
        since: '',
      );
    }
  }
  file
    ..truncateSync(0)
    ..writeStringSync(jsonEncode(me.toJson()))
    ..flushSync();
  _held = file;
  return null;
}

/// Lets go of this process's lock (tests; the app holds it until it ends).
void releaseDataFolderLock() {
  _held?.closeSync();
  _held = null;
}

// ── Reading the folder ──────────────────────────────────────────────────

final _dailyBackup = RegExp(r'^lodging_pos-\d{4}-\d{2}-\d{2}-\d{4}\.sqlite$');
final _besideBackup = RegExp(r'^lodging_pos\.sqlite\.(v\d+\.bak|bak-.+)$');

/// What [folder] holds, read without changing anything: the live file is
/// opened read-only and closed again.
Future<DeskInspection> inspectDataFolder(
  String folder, {
  LockHolder? heldBy,
}) async {
  final dir = Directory(folder);
  if (!dir.existsSync()) return DeskInspection(heldBy: heldBy);
  final names = [
    for (final e in dir.listSync())
      (e, e.uri.pathSegments.lastWhere((s) => s.isNotEmpty)),
  ];
  final backups = Directory(_join(folder, 'backups'));
  final hasBackups =
      names.any(
        (n) =>
            (n.$1 is File && _besideBackup.hasMatch(n.$2)) ||
            (n.$1 is Directory && n.$2.startsWith('reset-')),
      ) ||
      (backups.existsSync() &&
          backups.listSync().any(
            (e) => e is File && _dailyBackup.hasMatch(e.uri.pathSegments.last),
          ));
  final file = File(_join(folder, databaseFileName));
  final live = file.existsSync() && file.lengthSync() > 0
      ? await readLiveFile(file.path)
      : null;
  return DeskInspection(
    live: live,
    hasBackups: hasBackups,
    mark: readMark(folder),
    heldBy: heldBy,
  );
}

/// The live file's figures and this desk's facts, read-only.
Future<LiveFile> readLiveFile(String path) async {
  final db = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
  try {
    Object? scalar(String query) {
      final rows = db.select(query);
      return rows.isEmpty ? null : rows.first.values.first;
    }

    final figures = await figuresOf(scalar, schema: 'main');
    final tables = await tablesOf(scalar, 'main');
    String? meta(String key) => tables.contains('sync_state')
        ? scalar("SELECT value FROM sync_state WHERE key = '$key'") as String?
        : null;
    final build = int.tryParse(meta(DeskMetaKeys.build) ?? '');
    final next = tables.contains('receipt_counter') && tables.contains('device')
        ? scalar(
            'SELECT next_number FROM receipt_counter WHERE device_id = '
            '(SELECT device_id FROM device LIMIT 1)',
          )
        : null;
    return LiveFile(
      figures: figures,
      stamp: build == null
          ? null
          : DeskStamp(version: meta(DeskMetaKeys.version) ?? '?', build: build),
      installPath: meta(DeskMetaKeys.installPath),
      everConnected: meta('desk_email') != null || meta('upload.done') != null,
      ownerEmail: meta('owner_email'),
      deviceId: tables.contains('device')
          ? scalar('SELECT device_id FROM device LIMIT 1') as String?
          : null,
      nextReceiptNumber: next is int ? next : 1,
    );
  } finally {
    db.close();
  }
}

/// The owner's id, password hash and whether the account is active, read
/// read-only from the live file in [folder] (accepting a restore happens
/// before the file is opened for writing); null if there is no owner.
({String id, String passwordHash, bool isActive})? readOwnerFromFile(
  String folder,
) {
  final file = File(_join(folder, databaseFileName));
  if (!file.existsSync()) return null;
  final db = sql.sqlite3.open(file.path, mode: sql.OpenMode.readOnly);
  try {
    final rows = db.select(
      "SELECT id, password_hash, is_active FROM users WHERE role = 'owner' "
      'LIMIT 1',
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      id: r['id'] as String,
      passwordHash: r['password_hash'] as String,
      isActive: r['is_active'] == 1,
    );
  } finally {
    db.close();
  }
}

// ── The high-water mark ─────────────────────────────────────────────────

/// The mark next to the database in [folder]; null if there is none or it
/// can't be read.
HighWaterMark? readMark(String folder) {
  final file = File(_join(folder, markFileName));
  if (!file.existsSync()) return null;
  try {
    return HighWaterMark.fromJson(
      (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>(),
    );
  } on Object {
    return null;
  }
}

/// Writes [mark] whole: a `.partial` file first, then renamed over the old.
void writeMark(String folder, HighWaterMark mark) {
  final target = _join(folder, markFileName);
  final partial = File('$target.partial')
    ..writeAsStringSync(jsonEncode(mark.toJson()), flush: true);
  partial.renameSync(target);
}

// ── Upgrades ────────────────────────────────────────────────────────────

/// The app's [BeforeMigration]: copies its database file aside before
/// upgrading it, in every build (see [copyBeforeMigration]).
Future<void> backUpBeforeMigration(GeneratedDatabase db, int from) async {
  await copyBeforeMigration(db, await databaseFilePath(), from);
}

/// How many pre-migration copies are kept.
const keptMigrationBackups = 2;

/// Copies the open database [db], whose file is [path], to
/// `<path>.v<from>.bak` before a migration from version [from], then
/// deletes all but the [keptMigrationBackups] newest such copies. Returns
/// the copy's path.
///
/// `VACUUM INTO` writes a consistent copy of the open database, including
/// anything still in the WAL. It goes to a `.partial` file first, so a
/// failed copy never replaces a good one (e.g. from an earlier attempt).
Future<String> copyBeforeMigration(
  GeneratedDatabase db,
  String path,
  int from,
) async {
  final target = '$path.v$from.bak';
  final partial = File('$target.partial');
  if (partial.existsSync()) partial.deleteSync();
  await db.customStatement('VACUUM INTO ?', [partial.path]);
  final old = File(target);
  if (old.existsSync()) old.deleteSync();
  partial.renameSync(target);

  final file = File(path);
  final names = [
    for (final entity in file.parent.listSync())
      if (entity is File) entity.uri.pathSegments.last,
  ];
  for (final name in staleMigrationBackups(file.uri.pathSegments.last, names)) {
    File('${file.parent.path}${Platform.pathSeparator}$name').deleteSync();
  }
  return target;
}

/// Of [names] (files next to the database [fileName]), the pre-migration
/// copies (`<fileName>.v<n>.bak`) to delete: all but the [keep] with the
/// highest versions.
List<String> staleMigrationBackups(
  String fileName,
  Iterable<String> names, {
  int keep = keptMigrationBackups,
}) {
  final pattern = RegExp('^${RegExp.escape(fileName)}\\.v(\\d+)\\.bak\$');
  final backups = [
    for (final name in names)
      if (pattern.firstMatch(name) case final m?) (name, int.parse(m[1]!)),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (name, _) in backups.skip(keep)) name];
}

// ── The debug reset ─────────────────────────────────────────────────────

/// The reset couldn't make a good copy first; nothing was moved.
final class ResetRefused implements Exception {
  const ResetRefused(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Debug builds only, after a typed confirmation: the closed database in
/// [folder] is copied into `reset-YYYYMMDD-HHMMSS/copy` (Nairobi time) and
/// the copy checked; only then are the file, its side files and the mark
/// moved into `reset-…`. Nothing is deleted. Returns the reset folder.
String resetDatabaseFiles(String folder, DateTime now) {
  final local = toNairobi(now);
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${local.year}${two(local.month)}${two(local.day)}-'
      '${two(local.hour)}${two(local.minute)}${two(local.second)}';
  final target = _join(folder, 'reset-$stamp');
  final copy = _join(target, 'copy');
  Directory(copy).createSync(recursive: true);
  const sides = ['', '-wal', '-shm', '-journal'];
  for (final suffix in sides) {
    final file = File(_join(folder, '$databaseFileName$suffix'));
    if (file.existsSync()) {
      file.copySync(_join(copy, '$databaseFileName$suffix'));
    }
  }
  try {
    final checked = sql.sqlite3.open(
      _join(copy, databaseFileName),
      mode: sql.OpenMode.readOnly,
    );
    try {
      final result = checked.select('PRAGMA integrity_check');
      if (result.length != 1 || result.first.values.first != 'ok') {
        throw const ResetRefused('The copy failed its check.');
      }
    } finally {
      checked.close();
    }
  } on ResetRefused {
    rethrow;
  } on Object catch (e) {
    throw ResetRefused('The copy failed its check: $e');
  }
  for (final name in [
    for (final suffix in sides) '$databaseFileName$suffix',
    markFileName,
  ]) {
    final file = File(_join(folder, name));
    if (file.existsSync()) file.renameSync(_join(target, name));
  }
  return target;
}

/// Debug builds: resets the app's own data folder.
Future<String> resetDataFolder(DateTime now) async =>
    resetDatabaseFiles(await dataFolder(), now);

// ── Where the app runs from ─────────────────────────────────────────────

/// Whether [path] is on a removable drive (a USB stick or card), from
/// Windows' `GetDriveTypeW`. Other platforms and network paths: false.
bool isRemovableDrive(String path) {
  if (!Platform.isWindows) return false;
  final drive = RegExp(r'^([A-Za-z]:)').firstMatch(path);
  if (drive == null) return false;
  final getDriveType = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)
      >('GetDriveTypeW');
  final root = '${drive[1]}\\'.toNativeUtf16(allocator: calloc);
  try {
    const driveRemovable = 2;
    return getDriveType(root) == driveRemovable;
  } finally {
    calloc.free(root);
  }
}

/// Writes the high-water mark into the app's data folder.
Future<void> writeMarkToDataFolder(HighWaterMark mark) async =>
    writeMark(await dataFolder(), mark);
