// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Where the main backups go, or null where the desk takes none: web, the
/// admin phone, and tests unless they set a folder.

@ProviderFor(backupFolder)
final backupFolderProvider = BackupFolderProvider._();

/// Where the main backups go, or null where the desk takes none: web, the
/// admin phone, and tests unless they set a folder.

final class BackupFolderProvider
    extends
        $FunctionalProvider<
          Future<String> Function()?,
          Future<String> Function()?,
          Future<String> Function()?
        >
    with $Provider<Future<String> Function()?> {
  /// Where the main backups go, or null where the desk takes none: web, the
  /// admin phone, and tests unless they set a folder.
  BackupFolderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupFolderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupFolderHash();

  @$internal
  @override
  $ProviderElement<Future<String> Function()?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Future<String> Function()? create(Ref ref) {
    return backupFolder(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Future<String> Function()? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Future<String> Function()?>(value),
    );
  }
}

String _$backupFolderHash() => r'42afaae1ae7b3821be3e8aa421b3db322158fb53';

/// How often a running desk checks that today has a backup. Null in tests,
/// which call [Backups.checkNow] themselves.

@ProviderFor(backupCheckInterval)
final backupCheckIntervalProvider = BackupCheckIntervalProvider._();

/// How often a running desk checks that today has a backup. Null in tests,
/// which call [Backups.checkNow] themselves.

final class BackupCheckIntervalProvider
    extends $FunctionalProvider<Duration?, Duration?, Duration?>
    with $Provider<Duration?> {
  /// How often a running desk checks that today has a backup. Null in tests,
  /// which call [Backups.checkNow] themselves.
  BackupCheckIntervalProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupCheckIntervalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupCheckIntervalHash();

  @$internal
  @override
  $ProviderElement<Duration?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration? create(Ref ref) {
    return backupCheckInterval(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration?>(value),
    );
  }
}

String _$backupCheckIntervalHash() =>
    r'38c82a4b6e47708dc08e9594765453a0bcd392e6';

@ProviderFor(backupShell)
final backupShellProvider = BackupShellProvider._();

final class BackupShellProvider
    extends $FunctionalProvider<BackupShell, BackupShell, BackupShell>
    with $Provider<BackupShell> {
  BackupShellProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupShellProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupShellHash();

  @$internal
  @override
  $ProviderElement<BackupShell> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BackupShell create(Ref ref) {
    return backupShell(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupShell value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupShell>(value),
    );
  }
}

String _$backupShellHash() => r'26e23bb21edf2f85238249da64f3814cf2dd6022';

/// The daily local backup: once the database check has passed at start,
/// then every [backupCheckInterval], it backs up if today (Nairobi) has no
/// backup yet; also after every shift close and on "Back up now". One
/// backup at a time: a request made while one runs waits, then takes its
/// own, so a shift closed mid-backup is still in a copy. It never blocks
/// the desk.

@ProviderFor(Backups)
final backupsProvider = BackupsProvider._();

/// The daily local backup: once the database check has passed at start,
/// then every [backupCheckInterval], it backs up if today (Nairobi) has no
/// backup yet; also after every shift close and on "Back up now". One
/// backup at a time: a request made while one runs waits, then takes its
/// own, so a shift closed mid-backup is still in a copy. It never blocks
/// the desk.
final class BackupsProvider extends $NotifierProvider<Backups, BackupStatus> {
  /// The daily local backup: once the database check has passed at start,
  /// then every [backupCheckInterval], it backs up if today (Nairobi) has no
  /// backup yet; also after every shift close and on "Back up now". One
  /// backup at a time: a request made while one runs waits, then takes its
  /// own, so a shift closed mid-backup is still in a copy. It never blocks
  /// the desk.
  BackupsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupsHash();

  @$internal
  @override
  Backups create() => Backups();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupStatus>(value),
    );
  }
}

String _$backupsHash() => r'7e5f029552771b69bf1f00d7171ea1cf80d940e4';

/// The daily local backup: once the database check has passed at start,
/// then every [backupCheckInterval], it backs up if today (Nairobi) has no
/// backup yet; also after every shift close and on "Back up now". One
/// backup at a time: a request made while one runs waits, then takes its
/// own, so a shift closed mid-backup is still in a copy. It never blocks
/// the desk.

abstract class _$Backups extends $Notifier<BackupStatus> {
  BackupStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<BackupStatus, BackupStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BackupStatus, BackupStatus>,
              BackupStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
