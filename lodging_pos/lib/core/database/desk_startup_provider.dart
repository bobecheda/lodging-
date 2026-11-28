import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database_files.dart';
import 'desk_startup.dart';

part 'desk_startup_provider.g.dart';

/// The startup checks' outcome (story/desk-db-guards), made in `main()`
/// before anything opens the database and passed in as an override. Tests,
/// web and the phone get [DeskStartup.none]: nothing to check.
@Riverpod(keepAlive: true)
DeskStartup deskStartup(Ref ref) => DeskStartup.none;

/// The two high-water marks (the data folder's and the second copy), raised
/// after each backup and each operation in [markActions]; null where the
/// desk has no data folder (tests unless they set one).
@Riverpod(keepAlive: true)
MarkStore? markStore(Ref ref) =>
    switch (ref.watch(deskStartupProvider).folder) {
      final folder? => markStoreFor(folder),
      null => null,
    };
