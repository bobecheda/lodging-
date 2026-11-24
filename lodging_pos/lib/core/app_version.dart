/// This build's version, as in `pubspec.yaml` (`version: 1.0.0+2`).
/// `test/policy/app_version_test.dart` fails if the two differ.
const appVersionName = '1.0.0';

/// The build number after the `+` in `pubspec.yaml`. Release builds bump
/// it; a database stamped by a higher one is refused (docs/backup-restore.md).
const appBuildNumber = 2;

/// The commit this build was made from, passed at build time with
/// `--dart-define=APP_COMMIT=<short sha>`; "dev" without it.
const appCommit = String.fromEnvironment('APP_COMMIT', defaultValue: 'dev');

/// The schema version this build's database is at (`AppDatabase.
/// schemaVersion`; `test/policy/app_version_test.dart` checks they match).
/// Here as a constant so screens without a database can show it.
const latestSchemaVersion = 11;

/// The version a database records: which build last opened it.
final class DeskStamp {
  const DeskStamp({required this.version, required this.build});

  final String version;
  final int build;

  /// "desk 1.1.0 (build 3)".
  String get label => 'desk $version (build $build)';

  @override
  bool operator ==(Object other) =>
      other is DeskStamp && other.version == version && other.build == build;

  @override
  int get hashCode => Object.hash(version, build);

  @override
  String toString() => label;
}

/// A build of the desk app.
final class AppBuild {
  const AppBuild({
    required this.version,
    required this.build,
    this.commit = 'dev',
  });

  /// This build.
  static const current = AppBuild(
    version: appVersionName,
    build: appBuildNumber,
    commit: appCommit,
  );

  final String version;
  final int build;
  final String commit;

  DeskStamp get stamp => DeskStamp(version: version, build: build);

  /// "desk 1.1.0 (build 3)".
  String get label => stamp.label;
}

/// "Desk 1.1.0 (build 3) · abc1234 · database v11": the sign-in footer, the
/// user menu, the drawer and every refusal.
String versionLine(AppBuild build, {required int schemaVersion}) =>
    'Desk ${build.version} (build ${build.build}) · ${build.commit} · '
    'database v$schemaVersion';
