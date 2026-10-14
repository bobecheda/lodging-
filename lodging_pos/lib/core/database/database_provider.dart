import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../clock/clock.dart';
import 'database.dart';

part 'database_provider.g.dart';

/// The local database runs on native builds (Windows desk, Android). The web
/// admin build has no DriftWebOptions/wasm assets yet; sprint 2 decides
/// whether it needs a local database at all.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  if (kIsWeb) {
    throw UnsupportedError('The local database is not available on web.');
  }
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
