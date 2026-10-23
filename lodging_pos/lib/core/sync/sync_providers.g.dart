// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Supabase project, from `secrets.json` at build time
/// (`--dart-define-from-file`); null in a build without it: the desk
/// works locally and its pill says sync isn't set up.

@ProviderFor(cloud)
final cloudProvider = CloudProvider._();

/// The Supabase project, from `secrets.json` at build time
/// (`--dart-define-from-file`); null in a build without it: the desk
/// works locally and its pill says sync isn't set up.

final class CloudProvider extends $FunctionalProvider<Cloud?, Cloud?, Cloud?>
    with $Provider<Cloud?> {
  /// The Supabase project, from `secrets.json` at build time
  /// (`--dart-define-from-file`); null in a build without it: the desk
  /// works locally and its pill says sync isn't set up.
  CloudProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cloudProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cloudHash();

  @$internal
  @override
  $ProviderElement<Cloud?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Cloud? create(Ref ref) {
    return cloud(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Cloud? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Cloud?>(value),
    );
  }
}

String _$cloudHash() => r'b6868c33c5ab65a75ad6ed84ee325378f1a6f00c';

@ProviderFor(deskSecretStore)
final deskSecretStoreProvider = DeskSecretStoreProvider._();

final class DeskSecretStoreProvider
    extends
        $FunctionalProvider<DeskSecretStore, DeskSecretStore, DeskSecretStore>
    with $Provider<DeskSecretStore> {
  DeskSecretStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deskSecretStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deskSecretStoreHash();

  @$internal
  @override
  $ProviderElement<DeskSecretStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DeskSecretStore create(Ref ref) {
    return deskSecretStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeskSecretStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeskSecretStore>(value),
    );
  }
}

String _$deskSecretStoreHash() => r'ce7dc8efae11169fdcf97b441a763fdf39f7db76';

/// How often the queue is pushed (and the heartbeat every ten of these);
/// null turns the timers off (tests).

@ProviderFor(syncInterval)
final syncIntervalProvider = SyncIntervalProvider._();

/// How often the queue is pushed (and the heartbeat every ten of these);
/// null turns the timers off (tests).

final class SyncIntervalProvider
    extends $FunctionalProvider<Duration?, Duration?, Duration?>
    with $Provider<Duration?> {
  /// How often the queue is pushed (and the heartbeat every ten of these);
  /// null turns the timers off (tests).
  SyncIntervalProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncIntervalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncIntervalHash();

  @$internal
  @override
  $ProviderElement<Duration?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration? create(Ref ref) {
    return syncInterval(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration?>(value),
    );
  }
}

String _$syncIntervalHash() => r'0a557acbbb821b6e970ffc7c82d6cd6ffd7f3823';

/// This desk's sync, started with the app; null without a cloud.

@ProviderFor(syncEngine)
final syncEngineProvider = SyncEngineProvider._();

/// This desk's sync, started with the app; null without a cloud.

final class SyncEngineProvider
    extends $FunctionalProvider<SyncEngine?, SyncEngine?, SyncEngine?>
    with $Provider<SyncEngine?> {
  /// This desk's sync, started with the app; null without a cloud.
  SyncEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncEngineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncEngineHash();

  @$internal
  @override
  $ProviderElement<SyncEngine?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SyncEngine? create(Ref ref) {
    return syncEngine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncEngine? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncEngine?>(value),
    );
  }
}

String _$syncEngineHash() => r'cd7eca035c896786f9e5c76148a4a848a6f7dd0d';

/// The cloud-first writes for repositories (null: local only).

@ProviderFor(cloudWrites)
final cloudWritesProvider = CloudWritesProvider._();

/// The cloud-first writes for repositories (null: local only).

final class CloudWritesProvider
    extends $FunctionalProvider<CloudWrites?, CloudWrites?, CloudWrites?>
    with $Provider<CloudWrites?> {
  /// The cloud-first writes for repositories (null: local only).
  CloudWritesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cloudWritesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cloudWritesHash();

  @$internal
  @override
  $ProviderElement<CloudWrites?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CloudWrites? create(Ref ref) {
    return cloudWrites(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CloudWrites? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CloudWrites?>(value),
    );
  }
}

String _$cloudWritesHash() => r'9551440231672dd97138a0b04ffdbbec093aa006';

/// What the sync pill shows.

@ProviderFor(syncStatus)
final syncStatusProvider = SyncStatusProvider._();

/// What the sync pill shows.

final class SyncStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<SyncStatus>,
          SyncStatus,
          Stream<SyncStatus>
        >
    with $FutureModifier<SyncStatus>, $StreamProvider<SyncStatus> {
  /// What the sync pill shows.
  SyncStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncStatusHash();

  @$internal
  @override
  $StreamProviderElement<SyncStatus> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<SyncStatus> create(Ref ref) {
    return syncStatus(ref);
  }
}

String _$syncStatusHash() => r'46d6e2ef0edd1f1f37d05cd1c64e69866565e59c';
