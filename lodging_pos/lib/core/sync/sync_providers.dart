import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audit/audit_writer.dart';
import '../clock/clock.dart';
import '../database/database_provider.dart';
import 'cloud.dart';
import 'cloud_writes.dart';
import 'desk_secret_store.dart';
import 'supabase_cloud.dart';
import 'sync_engine.dart';

part 'sync_providers.g.dart';

/// The Supabase project, from `secrets.json` at build time
/// (`--dart-define-from-file`); null in a build without it: the desk
/// works locally and its pill says sync isn't set up.
@Riverpod(keepAlive: true)
Cloud? cloud(Ref ref) {
  const url = String.fromEnvironment('SUPABASE_URL');
  const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || anonKey.isEmpty) return null;
  return SupabaseCloud(url: url, anonKey: anonKey);
}

@Riverpod(keepAlive: true)
DeskSecretStore deskSecretStore(Ref ref) => SecureDeskSecretStore();

/// How often the queue is pushed (and the heartbeat every ten of these);
/// null turns the timers off (tests).
@Riverpod(keepAlive: true)
Duration? syncInterval(Ref ref) => const Duration(seconds: 30);

/// This desk's sync, started with the app; null without a cloud.
@Riverpod(keepAlive: true)
SyncEngine? syncEngine(Ref ref) {
  final cloud = ref.watch(cloudProvider);
  if (cloud == null) return null;
  final audit = ref.watch(auditWriterProvider);
  final every = ref.watch(syncIntervalProvider);
  final engine = SyncEngine(
    db: ref.watch(appDatabaseProvider),
    audit: audit,
    cloud: cloud,
    secrets: ref.watch(deskSecretStoreProvider),
    clock: ref.watch(clockProvider),
    pushEvery: every,
    heartbeatEvery: every == null ? null : every * 10,
  );
  audit.onCommit = engine.nudge;
  unawaited(engine.start());
  ref.onDispose(() {
    audit.onCommit = null;
    unawaited(engine.dispose());
  });
  return engine;
}

/// The cloud-first writes for repositories (null: local only).
@Riverpod(keepAlive: true)
CloudWrites? cloudWrites(Ref ref) => ref.watch(syncEngineProvider);

/// What the sync pill shows.
@Riverpod(keepAlive: true)
Stream<SyncStatus> syncStatus(Ref ref) async* {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) {
    yield const SyncStatus(phase: SyncPhase.notConfigured);
    return;
  }
  yield engine.status;
  yield* engine.changes;
}
