import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/startup/desk_root.dart';
import 'core/app_version.dart';
import 'core/database/database_files.dart';
import 'core/database/desk_startup.dart';

/// The desk. Before anything opens the database, the startup checks lock
/// the data folder and read it (docs/backup-restore.md, "Startup checks");
/// a refused database is never opened.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Future<DeskStartup> check() => runDeskStartup(
    build: AppBuild.current,
    schemaVersion: latestSchemaVersion,
    // Debug builds run from build\…\Debug: no install folder to compare.
    checkLocation: kReleaseMode,
  );
  runApp(DeskRoot(startup: await check(), check: check));
}
