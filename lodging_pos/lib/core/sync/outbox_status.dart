import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database_provider.dart';

part 'outbox_status.g.dart';

/// Changes written on this desk and not yet sent to the cloud (unsent
/// outbox rows). Sync arrives in sprint 2; until then this only grows.
@Riverpod(keepAlive: true)
Stream<int> pendingChanges(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  final count = countAll(filter: db.outbox.sentAt.isNull());
  return (db.selectOnly(
    db.outbox,
  )..addColumns([count])).map((row) => row.read(count)!).watchSingle();
}
