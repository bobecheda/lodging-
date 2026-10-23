import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session.dart';
import '../core/sync/sync_providers.dart';
import '../features/backup/presentation/backup_providers.dart';
import 'activity_detector.dart';
import 'router.dart';
import 'theme/theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Starts the daily backup once the database check passes; it then runs
    // on its own (docs/backup-restore.md).
    ref.listen(backupsProvider, (_, _) {});
    // Sync starts with the app (nothing to do without a cloud).
    ref.listen(syncEngineProvider, (_, _) {});
    // Signing out (or the screen locking) ends the owner's cloud sign-in.
    ref.listen(sessionProvider, (previous, next) {
      final engine = ref.read(syncEngineProvider);
      if (previous != null && next == null && engine != null) {
        unawaited(engine.ownerLeft());
      }
    });
    return MaterialApp.router(
      title: 'Lodging POS',
      theme: buildLodgingTheme(),
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      // Above the navigator, so activity on every screen and dialog counts.
      builder: (context, child) => ActivityDetector(child: child!),
    );
  }
}
