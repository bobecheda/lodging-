// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'idle_lock.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// How often to check for inactivity while someone is signed in. Tests
/// override it with null and call [IdleLock.check] themselves.

@ProviderFor(idleCheckInterval)
final idleCheckIntervalProvider = IdleCheckIntervalProvider._();

/// How often to check for inactivity while someone is signed in. Tests
/// override it with null and call [IdleLock.check] themselves.

final class IdleCheckIntervalProvider
    extends $FunctionalProvider<Duration?, Duration?, Duration?>
    with $Provider<Duration?> {
  /// How often to check for inactivity while someone is signed in. Tests
  /// override it with null and call [IdleLock.check] themselves.
  IdleCheckIntervalProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'idleCheckIntervalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$idleCheckIntervalHash();

  @$internal
  @override
  $ProviderElement<Duration?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration? create(Ref ref) {
    return idleCheckInterval(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration?>(value),
    );
  }
}

String _$idleCheckIntervalHash() => r'b2824bf341ea48c5e5a79b0069afb6c06ad7ab70';

/// Signs the user out after `idle_lock_minutes` without activity. The shift
/// stays open; only the session ends.
///
/// State: the idle minutes of the last automatic lock, so the login screen
/// can say why; null otherwise.

@ProviderFor(IdleLock)
final idleLockProvider = IdleLockProvider._();

/// Signs the user out after `idle_lock_minutes` without activity. The shift
/// stays open; only the session ends.
///
/// State: the idle minutes of the last automatic lock, so the login screen
/// can say why; null otherwise.
final class IdleLockProvider extends $NotifierProvider<IdleLock, int?> {
  /// Signs the user out after `idle_lock_minutes` without activity. The shift
  /// stays open; only the session ends.
  ///
  /// State: the idle minutes of the last automatic lock, so the login screen
  /// can say why; null otherwise.
  IdleLockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'idleLockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$idleLockHash();

  @$internal
  @override
  IdleLock create() => IdleLock();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$idleLockHash() => r'ac528b40ee27401db1890d01423feb54a63aa128';

/// Signs the user out after `idle_lock_minutes` without activity. The shift
/// stays open; only the session ends.
///
/// State: the idle minutes of the last automatic lock, so the login screen
/// can say why; null otherwise.

abstract class _$IdleLock extends $Notifier<int?> {
  int? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int?, int?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int?, int?>,
              int?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
