import 'package:drift/drift.dart';

import '../app_version.dart';
import 'desk_startup.dart';

// Web: there is no local database file, so nothing to check or move.

/// No in-memory database on this platform.
QueryExecutor? inMemoryExecutor() => null;

Future<DeskStartup> runDeskStartup({
  required AppBuild build,
  required int schemaVersion,
  required bool checkLocation,
}) async => DeskStartup.none;

Future<String> resetDataFolder(DateTime now) =>
    throw UnsupportedError('There is no local database file on this platform.');

Future<void> backUpBeforeMigration(GeneratedDatabase db, int from) =>
    throw UnsupportedError('There is no local database file on this platform.');

MarkStore markStoreFor(String folder) => const NoMarks();

({String id, String passwordHash, bool isActive})? readOwnerFromFile(
  String folder,
) => null;
