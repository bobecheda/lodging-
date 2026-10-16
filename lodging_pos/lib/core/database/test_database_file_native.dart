import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../clock/nairobi.dart';
import 'database_provider.dart';

/// A fresh in-memory database, to compare a file's schema against.
QueryExecutor? inMemoryExecutor() => NativeDatabase.memory();

/// Renames the closed database file (and any SQLite side files) to
/// `lodging_pos.sqlite.bak-YYYYMMDD-HHMMSS` (Nairobi time) in the same folder. Returns the
/// backup's path.
Future<String> backUpDatabaseFile(DateTime now) async {
  final dir = await getApplicationSupportDirectory();
  return moveDatabaseAside(
    '${dir.path}${Platform.pathSeparator}$databaseName.sqlite',
    toNairobi(now),
  );
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
