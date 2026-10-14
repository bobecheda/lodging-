import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../clock/clock.dart';
import 'database.dart';

part 'database_provider.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase(
    driftDatabase(
      name: 'lodging_pos',
      // App support dir, not Documents: the database is not a user document.
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    ),
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(db.close);
  return db;
}
