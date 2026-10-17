// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The local database runs on native builds (Windows desk, Android). The web
/// admin build has no DriftWebOptions/wasm assets yet; sprint 2 decides
/// whether it needs a local database at all.

@ProviderFor(appDatabase)
final appDatabaseProvider = AppDatabaseProvider._();

/// The local database runs on native builds (Windows desk, Android). The web
/// admin build has no DriftWebOptions/wasm assets yet; sprint 2 decides
/// whether it needs a local database at all.

final class AppDatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  /// The local database runs on native builds (Windows desk, Android). The web
  /// admin build has no DriftWebOptions/wasm assets yet; sprint 2 decides
  /// whether it needs a local database at all.
  AppDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDatabaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return appDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$appDatabaseHash() => r'6bb44451d40424bef006e3162ff937958ca0654c';
