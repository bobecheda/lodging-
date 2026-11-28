// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'startup_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Once the database check passes, on the real desk only (story/desk-db-
/// guards): finish an accepted restore, raise the file's build stamp, and
/// record the install folder on the first run. Since story/desk-db-guards-2
/// the marks move with the work from here on, and a missing copy is written
/// again. Sign-in waits for it.

@ProviderFor(startupTasks)
final startupTasksProvider = StartupTasksProvider._();

/// Once the database check passes, on the real desk only (story/desk-db-
/// guards): finish an accepted restore, raise the file's build stamp, and
/// record the install folder on the first run. Since story/desk-db-guards-2
/// the marks move with the work from here on, and a missing copy is written
/// again. Sign-in waits for it.

final class StartupTasksProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  /// Once the database check passes, on the real desk only (story/desk-db-
  /// guards): finish an accepted restore, raise the file's build stamp, and
  /// record the install folder on the first run. Since story/desk-db-guards-2
  /// the marks move with the work from here on, and a missing copy is written
  /// again. Sign-in waits for it.
  StartupTasksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'startupTasksProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startupTasksHash();

  @$internal
  @override
  $FutureProviderElement<void> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<void> create(Ref ref) {
    return startupTasks(ref);
  }
}

String _$startupTasksHash() => r'986e8afc5db5318c749ed07ac887a4edd2f92307';

/// Before sign-in, on a connected desk that is online
/// (story/desk-db-guards-2): asks the cloud whether this file is behind it
/// (`SyncEngine.checkCloud`). Offline, refused or slower than
/// [cloudCheckWait], the desk opens as today; the engine asks again before
/// it sends anything.

@ProviderFor(cloudStartupCheck)
final cloudStartupCheckProvider = CloudStartupCheckProvider._();

/// Before sign-in, on a connected desk that is online
/// (story/desk-db-guards-2): asks the cloud whether this file is behind it
/// (`SyncEngine.checkCloud`). Offline, refused or slower than
/// [cloudCheckWait], the desk opens as today; the engine asks again before
/// it sends anything.

final class CloudStartupCheckProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  /// Before sign-in, on a connected desk that is online
  /// (story/desk-db-guards-2): asks the cloud whether this file is behind it
  /// (`SyncEngine.checkCloud`). Offline, refused or slower than
  /// [cloudCheckWait], the desk opens as today; the engine asks again before
  /// it sends anything.
  CloudStartupCheckProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cloudStartupCheckProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cloudStartupCheckHash();

  @$internal
  @override
  $FutureProviderElement<void> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<void> create(Ref ref) {
    return cloudStartupCheck(ref);
  }
}

String _$cloudStartupCheckHash() => r'242634c44db35043324b6b4ef8ec50b599df4e7e';

/// Accepting an older backup from the refusal screen, before the database
/// opens: the owner's account is read from the file read-only.

@ProviderFor(restoreAcceptance)
final restoreAcceptanceProvider = RestoreAcceptanceProvider._();

/// Accepting an older backup from the refusal screen, before the database
/// opens: the owner's account is read from the file read-only.

final class RestoreAcceptanceProvider
    extends
        $FunctionalProvider<
          RestoreAcceptance,
          RestoreAcceptance,
          RestoreAcceptance
        >
    with $Provider<RestoreAcceptance> {
  /// Accepting an older backup from the refusal screen, before the database
  /// opens: the owner's account is read from the file read-only.
  RestoreAcceptanceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'restoreAcceptanceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$restoreAcceptanceHash();

  @$internal
  @override
  $ProviderElement<RestoreAcceptance> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RestoreAcceptance create(Ref ref) {
    return restoreAcceptance(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RestoreAcceptance value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RestoreAcceptance>(value),
    );
  }
}

String _$restoreAcceptanceHash() => r'caf774efc7d188c57be3f4dbbd5c0f4396bfee35';

/// The unusual start still to be accepted, or null (story/desk-db-guards).

@ProviderFor(UnusualStart)
final unusualStartProvider = UnusualStartProvider._();

/// The unusual start still to be accepted, or null (story/desk-db-guards).
final class UnusualStartProvider
    extends $NotifierProvider<UnusualStart, UnusualLocation?> {
  /// The unusual start still to be accepted, or null (story/desk-db-guards).
  UnusualStartProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'unusualStartProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$unusualStartHash();

  @$internal
  @override
  UnusualStart create() => UnusualStart();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UnusualLocation? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UnusualLocation?>(value),
    );
  }
}

String _$unusualStartHash() => r'41ac13bc2a29297eccf58470738f6587f83817b1';

/// The unusual start still to be accepted, or null (story/desk-db-guards).

abstract class _$UnusualStart extends $Notifier<UnusualLocation?> {
  UnusualLocation? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<UnusualLocation?, UnusualLocation?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UnusualLocation?, UnusualLocation?>,
              UnusualLocation?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
