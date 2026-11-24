import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/app_version.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/database/database.dart';

import '../helpers/fixtures.dart';

/// The version on screen (story/desk-db-guards) must be the real one.
void main() {
  test('lib/core/app_version.dart matches pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(line.trim(), 'version: $appVersionName+$appBuildNumber');
  });

  test('latestSchemaVersion matches the database', () async {
    final db = AppDatabase(NativeDatabase.memory(), clock: FixedClock(testT0));
    addTearDown(db.close);
    expect(latestSchemaVersion, db.schemaVersion);
  });
}
