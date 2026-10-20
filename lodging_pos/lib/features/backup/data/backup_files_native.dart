import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// `<app support dir>/backups`, next to the database file and outside
/// Documents, so Windows doesn't sync it to OneDrive.
Future<String> defaultBackupFolder() async =>
    joinPath((await getApplicationSupportDirectory()).path, 'backups');

String joinPath(String folder, String name) =>
    '$folder${Platform.pathSeparator}$name';

Future<bool> folderExists(String folder) => Directory(folder).exists();

Future<void> createFolder(String folder) =>
    Directory(folder).create(recursive: true);

/// The names of the files directly in [folder]; empty if it doesn't exist.
Future<List<String>> fileNames(String folder) async {
  final dir = Directory(folder);
  if (!await dir.exists()) return [];
  return [
    await for (final entity in dir.list())
      if (entity is File) entity.uri.pathSegments.last,
  ];
}

Future<int> fileSize(String path) => File(path).length();

Future<void> deleteIfExists(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

/// Renames [from] to [to], replacing [to] if it exists.
Future<void> moveReplacing(String from, String to) async {
  await deleteIfExists(to);
  await File(from).rename(to);
}

Future<void> copyFile(String from, String to) => File(from).copy(to);

/// Why a backup couldn't be made, in plain words: the operating system's
/// reason (e.g. "There is not enough space on the disk") or SQLite's,
/// without exception types, statements or paths.
String describeFileError(Object error) {
  // SQLite's code, read from the text: the app's database runs in a
  // background isolate, which passes its errors back wrapped.
  if (_sqliteCode.firstMatch('$error') case final m?) {
    return switch (int.parse(m[1]!) & 0xff) {
      13 => 'The disk is full.', // SQLITE_FULL
      14 => 'The backup file couldn’t be written in the folder.', // CANTOPEN
      10 => 'The disk couldn’t be read or written.', // SQLITE_IOERR
      final code => 'The database couldn’t be copied (SQLite error $code).',
    };
  }
  return switch (error) {
    FileSystemException(:final osError?) => osError.message.trim(),
    FileSystemException(:final message) => message,
    _ => '$error',
  };
}

final _sqliteCode = RegExp(r'SqliteException\((\d+)\)');

/// The folder picker; null if cancelled.
Future<String?> pickFolder() =>
    getDirectoryPath(confirmButtonText: 'Use this folder');

/// Opens [path] in Explorer (Windows); elsewhere, the file manager.
Future<void> openFolder(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else {
    await Process.run('xdg-open', [path]);
  }
}
