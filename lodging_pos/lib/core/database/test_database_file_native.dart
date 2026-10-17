import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../clock/nairobi.dart';
import 'database_provider.dart';

/// A fresh in-memory database, to compare a file's schema against.
QueryExecutor? inMemoryExecutor() => NativeDatabase.memory();

/// `<app support dir>/lodging_pos.sqlite`.
Future<String> databaseFilePath() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}${Platform.pathSeparator}$databaseName.sqlite';
}

/// Renames the closed database file (and any SQLite side files) to
/// `lodging_pos.sqlite.bak-YYYYMMDD-HHMMSS` (Nairobi time) in the same folder. Returns the
/// backup's path.
Future<String> backUpDatabaseFile(DateTime now) async =>
    moveDatabaseAside(await databaseFilePath(), toNairobi(now));

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

/// Renames [path] and its `-wal`, `-shm` and `-journal` files, if present,
/// to `<path>.bak-YYYYMMDD-HHMMSS`. Nothing is deleted.
String moveDatabaseAside(String path, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  final backup = '$path.bak-$stamp';
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final file = File('$path$suffix');
    if (file.existsSync()) file.renameSync('$backup$suffix');
  }
  return backup;
}
