import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../clock/clock.dart';
import 'database.dart';
import 'database_provider.dart';
import 'test_database_file.dart';

part 'schema_check.g.dart';

/// The local database file was made by an older build: its tables, indexes
/// or triggers differ from what this build creates. Only possible while
/// schema v1 still changes in place (see CLAUDE.md, Workflow); after the
/// first install every change is a migration and this never fires.
final class SchemaDrift {
  const SchemaDrift(this.differences);

  /// e.g. `Changed: table bed_categories`, `Missing: table refunds`.
  final List<String> differences;
}

/// Compares every table, index and trigger in [live] with [expected] (a
/// fresh database from this build). Empty when they match.
Future<List<String>> schemaDifferences(
  GeneratedDatabase live,
  GeneratedDatabase expected,
) async {
  final have = await _objects(live);
  final want = await _objects(expected);
  return [
    for (final MapEntry(:key, :value) in want.entries)
      if (!have.containsKey(key))
        'Missing: $key'
      else if (have[key] != value)
        'Changed: $key',
    for (final key in have.keys)
      if (!want.containsKey(key)) 'Not expected: $key',
  ];
}

/// `type name` → its SQL, whitespace collapsed.
Future<Map<String, String>> _objects(GeneratedDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT type, name, sql FROM sqlite_master '
        "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
      )
      .get();
  return {
    for (final r in rows)
      '${r.read<String>('type')} ${r.read<String>('name')}':
          (r.readNullable<String>('sql') ?? '').replaceAll(RegExp(r'\s+'), ' '),
  };
}

/// Debug builds only: null when the database file matches this build (and
/// always null in release, on web, or where no in-memory database exists).
@Riverpod(keepAlive: true)
Future<SchemaDrift?> schemaDrift(Ref ref) async {
  if (!kDebugMode) return null;
  final live = ref.watch(appDatabaseProvider);
  final executor = inMemoryExecutor();
  if (executor == null) return null;
  final expected = AppDatabase(executor, clock: ref.watch(clockProvider));
  try {
    final differences = await schemaDifferences(live, expected);
    return differences.isEmpty ? null : SchemaDrift(differences);
  } finally {
    await expected.close();
  }
}

/// Closes the database, renames its file to a timestamped `.bak` next to it
/// (kept, not deleted) and reopens a fresh one. Returns the backup's path.
/// Overridden in tests, which use in-memory databases.
@Riverpod(keepAlive: true)
Future<String> Function() resetTestDatabase(Ref ref) => () async {
  await ref.read(appDatabaseProvider).close();
  final backup = await backUpDatabaseFile(ref.read(clockProvider).now());
  // Only now, with the old file moved away, may a new database open.
  ref.invalidate(appDatabaseProvider);
  return backup;
};
