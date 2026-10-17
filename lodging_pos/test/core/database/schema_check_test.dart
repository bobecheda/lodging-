import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/old_database_screen.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/schema_check.dart';
import 'package:lodging_pos/core/database/seed.dart';
import 'package:lodging_pos/core/database/test_database_file_native.dart';

import '../../helpers/fixtures.dart';

void main() {
  AppDatabase fresh() =>
      AppDatabase(NativeDatabase.memory(), clock: FixedClock(testT0));

  group('schemaDifferences', () {
    test('a database from this build matches', () async {
      final live = fresh();
      final expected = fresh();
      addTearDown(live.close);
      addTearDown(expected.close);
      expect(await schemaDifferences(live, expected), isEmpty);
    });

    test('names what an older build left different', () async {
      final live = fresh();
      final expected = fresh();
      addTearDown(live.close);
      addTearDown(expected.close);
      // As a file made before the per-night change would look.
      await live.customStatement(
        'ALTER TABLE bed_categories RENAME COLUMN price_per_night '
        'TO price_per_block',
      );
      await live.customStatement('DROP TRIGGER refunds_no_delete');
      await live.customStatement('CREATE TABLE old_stuff (x INTEGER)');

      final differences = await schemaDifferences(live, expected);
      expect(differences, contains('Changed: table bed_categories'));
      expect(differences, contains('Missing: trigger refunds_no_delete'));
      expect(differences, contains('Not expected: table old_stuff'));
    });
  });

  group('normalizeSchemaSql', () {
    test('spacing and identifier quotes are one spelling', () {
      expect(
        normalizeSchemaSql(
          'CREATE TABLE "x" ("a" TEXT NOT NULL REFERENCES stays(id), '
          'CHECK (a IN (\'p\', \'q\')))',
        ),
        normalizeSchemaSql(
          'CREATE TABLE x (a  TEXT\n NOT NULL REFERENCES stays (id),'
          'CHECK("a" IN (\'p\',\'q\')))',
        ),
      );
    });

    test('words stay apart: NOT NULL is not NOTNULL', () {
      expect(normalizeSchemaSql('a TEXT NOT NULL'), 'a TEXT NOT NULL');
    });
  });

  group('a real difference still fails the check', () {
    // (An upgraded v1 file passing it is in test/drift/…/migration_test.dart.)

    /// A fresh database with [table]'s CREATE statement edited from [from]
    /// to [to], compared with an untouched one.
    Future<List<String>> edited(String table, String from, String to) async {
      final live = fresh();
      final expected = fresh();
      addTearDown(live.close);
      addTearDown(expected.close);
      final sql =
          (await live
                  .customSelect(
                    'SELECT sql FROM sqlite_master WHERE name = ?',
                    variables: [Variable<String>(table)],
                  )
                  .getSingle())
              .read<String>('sql');
      expect(sql, contains(from));
      await live.customStatement('PRAGMA writable_schema = ON');
      await live.customStatement(
        'UPDATE sqlite_master SET sql = ? WHERE name = ?',
        [sql.replaceFirst(from, to), table],
      );
      await live.customStatement('PRAGMA writable_schema = OFF');
      return schemaDifferences(live, expected);
    }

    test('a missing column', () async {
      final live = fresh();
      final expected = fresh();
      addTearDown(live.close);
      addTearDown(expected.close);
      await live.customStatement(
        'ALTER TABLE stay_charges DROP COLUMN category_name',
      );
      expect(await schemaDifferences(live, expected), [
        'Changed: table stay_charges',
      ]);
    });

    test('a changed type (TEXT → INTEGER)', () async {
      expect(await edited('housekeepers', '"phone" TEXT', '"phone" INTEGER'), [
        'Changed: table housekeepers',
      ]);
    });

    test('a removed NOT NULL', () async {
      expect(
        await edited('guests', '"full_name" TEXT NOT NULL', '"full_name" TEXT'),
        ['Changed: table guests'],
      );
    });
  });

  test('gate: an old database comes before everything else', () {
    expect(
      routeFor(
        hasUsers: false,
        user: null,
        shiftStart: null,
        schemaMatches: false,
      ),
      Routes.oldDatabase,
    );
    expect(
      routeFor(
        hasUsers: true,
        user: null,
        shiftStart: null,
        schemaMatches: null,
      ),
      Routes.splash,
    );
    expect(
      routeFor(hasUsers: false, user: null, shiftStart: null),
      Routes.setup,
    );
  });

  testWidgets('an old database shows the reset screen; resetting goes on to '
      'first-run setup', (tester) async {
    final env = TestEnv();
    addTearDown(env.close);
    await env.db.customStatement(
      'ALTER TABLE bed_categories RENAME COLUMN price_per_night '
      'TO price_per_block',
    );
    var resets = 0;
    final app = await pumpDeskApp(
      tester,
      env,
      extraOverrides: [
        // Stands in for renaming the file: puts the schema right again.
        resetTestDatabaseProvider.overrideWithValue(() async {
          resets++;
          await env.db.customStatement(
            'ALTER TABLE bed_categories RENAME COLUMN price_per_block '
            'TO price_per_night',
          );
          return 'lodging_pos.sqlite.bak-test';
        }),
      ],
    );

    expect(locationOf(app), Routes.oldDatabase);
    expect(find.byType(OldDatabaseScreen), findsOneWidget);
    expect(
      find.text('This test database was made by an older build'),
      findsOneWidget,
    );
    expect(find.text('Changed: table bed_categories'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tapKey(tester, 'oldDatabase.reset');
    expect(resets, 1);
    expect(locationOf(app), Routes.setup);
    expect(find.text('Set up this lodging'), findsOneWidget);
  });

  testWidgets('a database that matches never shows it', (tester) async {
    final env = TestEnv();
    addTearDown(env.close);
    final app = await pumpDeskApp(tester, env);
    expect(locationOf(app), Routes.setup);
    expect(find.byType(OldDatabaseScreen), findsNothing);
    expect(find.byKey(const ValueKey('oldDatabase.reset')), findsNothing);
  });

  test('reset moves the file and its side files aside, deleting nothing', () {
    final dir = Directory.systemTemp.createTempSync('lodging_reset');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}lodging_pos.sqlite';
    File(path).writeAsStringSync('old');
    File('$path-wal').writeAsStringSync('wal');

    final backup = moveDatabaseAside(path, DateTime.utc(2026, 10, 16, 9, 5, 7));
    expect(backup, '$path.bak-20261016-090507');
    expect(File(path).existsSync(), isFalse);
    expect(File(backup).readAsStringSync(), 'old');
    expect(File('$backup-wal').readAsStringSync(), 'wal');
  });

  testWidgets('a release build explains but never offers a reset', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.close);
    await env.db.customStatement(
      'ALTER TABLE bed_categories RENAME COLUMN price_per_night '
      'TO price_per_block',
    );
    final app = await pumpDeskApp(
      tester,
      env,
      extraOverrides: [canResetDatabaseProvider.overrideWithValue(false)],
    );
    expect(locationOf(app), Routes.oldDatabase);
    expect(
      find.text('The database does not match this version'),
      findsOneWidget,
    );
    expect(find.textContaining('Your data is untouched.'), findsOneWidget);
    expect(find.byKey(const ValueKey('oldDatabase.reset')), findsNothing);
  });

  group('versions', () {
    test('a file from a newer version of the app is refused', () async {
      final dir = Directory.systemTemp.createTempSync('lodging_version');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}db.sqlite');

      final first = AppDatabase(
        NativeDatabase(file),
        clock: FixedClock(testT0),
      );
      await first.customStatement('PRAGMA user_version = 99');
      await first.close();

      final second = AppDatabase(
        NativeDatabase(file),
        clock: FixedClock(testT0),
      );
      addTearDown(second.close);
      await expectLater(
        second.select(second.settings).get(),
        throwsA(predicate((e) => '$e'.contains('made by a newer version'))),
      );
    });

    test('missing settings are added at their default; others untouched', () async {
      final db = fresh();
      addTearDown(db.close);
      await db.customStatement(
        "DELETE FROM settings WHERE key IN ('receipt_prefix', 'checkout_time')",
      );
      await db.customStatement(
        "UPDATE settings SET value = '45', updated_at = '2026-10-15T00:00:00.000Z' "
        "WHERE key = 'grace_minutes'",
      );
      await insertMissingSettings(db, now: testT0);
      final values = {
        for (final r in await db.select(db.settings).get()) r.key: r.value,
      };
      expect(values['receipt_prefix'], 'R');
      expect(values['checkout_time'], '10:00');
      expect(values['grace_minutes'], '45');
    });
  });
}
