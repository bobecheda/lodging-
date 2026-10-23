import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/sync/sync_store.dart';

/// The cloud mirrors the desk: every synced drift table and column is in
/// supabase/migrations, so a drift change can't ship without its cloud
/// migration (docs/sync.md).
void main() {
  late AppDatabase db;
  setUp(
    () => db = AppDatabase(
      NativeDatabase.memory(),
      clock: FixedClock(DateTime.utc(2026, 10, 23)),
    ),
  );
  tearDown(() => db.close());

  /// table → its columns, from every `create table public.X (...)`.
  Map<String, Set<String>> cloudTables() {
    final sql = [
      for (final f in Directory(
        '../supabase/migrations',
      ).listSync()..sort((a, b) => a.path.compareTo(b.path)))
        if (f is File && f.path.endsWith('.sql')) f.readAsStringSync(),
    ].join('\n').replaceAll('\r\n', '\n');
    final tables = RegExp(
      r'create table public\.(\w+) \((.*?)\n\);',
      dotAll: true,
    ).allMatches(sql);
    const notColumns = {'check', 'unique', 'primary', 'foreign', 'constraint'};
    return {
      for (final t in tables)
        t.group(1)!: {
          for (final line in t.group(2)!.split('\n'))
            if (RegExp(r'^  (\w+) ').firstMatch(line)?.group(1) case final name?
                when !notColumns.contains(name))
              name,
        },
    };
  }

  test('the upload lists name every synced table, once', () {
    const localOnly = {'outbox', 'device', 'receipt_counter', 'sync_state'};
    final synced = {
      for (final t in db.allTables)
        if (!localOnly.contains(t.actualTableName)) t.actualTableName,
    };
    final listed = [...SyncStore.deskTables, ...SyncStore.ownerTables];
    expect(listed.toSet(), synced);
    expect(listed, hasLength(synced.length));
  });

  test('every synced table and column is in the cloud; the cloud adds only '
      'server_seq (and the owner’s price time), and never a password hash', () {
    final cloud = cloudTables();
    for (final table in [...SyncStore.deskTables, ...SyncStore.ownerTables]) {
      final drift = db.allTables.firstWhere((t) => t.actualTableName == table);
      final expected = {
        for (final c in drift.$columns)
          if (c.name != 'password_hash') c.name,
        'server_seq',
        if (table == 'bed_categories') 'price_updated_at',
      };
      expect(cloud[table], expected, reason: table);
    }
  });
}
