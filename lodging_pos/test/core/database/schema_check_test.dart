import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/old_database_screen.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';
import 'package:lodging_pos/core/database/schema_check.dart';
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
}
