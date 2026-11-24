// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'startup_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Once the database check passes, on the real desk only (story/desk-db-
/// guards): finish an accepted restore, raise the file's build stamp, and
/// record the install folder on the first run. Sign-in waits for it.

@ProviderFor(startupTasks)
final startupTasksProvider = StartupTasksProvider._();

/// Once the database check passes, on the real desk only (story/desk-db-
/// guards): finish an accepted restore, raise the file's build stamp, and
/// record the install folder on the first run. Sign-in waits for it.

final class StartupTasksProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  /// Once the database check passes, on the real desk only (story/desk-db-
  /// guards): finish an accepted restore, raise the file's build stamp, and
  /// record the install folder on the first run. Sign-in waits for it.
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

String _$startupTasksHash() => r'd177429945c95745c53e46754f81b8951c736540';

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

String _$restoreAcceptanceHash() => r'0b4cdbb0432b137a72ac4aba95fca32d9bd8d478';

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
