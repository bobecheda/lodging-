import 'package:drift/drift.dart';

/// No in-memory database on this platform.
QueryExecutor? inMemoryExecutor() => null;

Future<String> backUpDatabaseFile(DateTime now) =>
    throw UnsupportedError('There is no local database file on this platform.');

Future<void> backUpBeforeMigration(GeneratedDatabase db, int from) =>
    throw UnsupportedError('There is no local database file on this platform.');
