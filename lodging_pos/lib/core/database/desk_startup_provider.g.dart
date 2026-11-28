// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'desk_startup_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The startup checks' outcome (story/desk-db-guards), made in `main()`
/// before anything opens the database and passed in as an override. Tests,
/// web and the phone get [DeskStartup.none]: nothing to check.

@ProviderFor(deskStartup)
final deskStartupProvider = DeskStartupProvider._();

/// The startup checks' outcome (story/desk-db-guards), made in `main()`
/// before anything opens the database and passed in as an override. Tests,
/// web and the phone get [DeskStartup.none]: nothing to check.

final class DeskStartupProvider
    extends $FunctionalProvider<DeskStartup, DeskStartup, DeskStartup>
    with $Provider<DeskStartup> {
  /// The startup checks' outcome (story/desk-db-guards), made in `main()`
  /// before anything opens the database and passed in as an override. Tests,
  /// web and the phone get [DeskStartup.none]: nothing to check.
  DeskStartupProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deskStartupProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deskStartupHash();

  @$internal
  @override
  $ProviderElement<DeskStartup> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DeskStartup create(Ref ref) {
    return deskStartup(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeskStartup value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeskStartup>(value),
    );
  }
}

String _$deskStartupHash() => r'f1fb2fab18e68dc934494d9b39e168164b7def96';

/// The two high-water marks (the data folder's and the second copy), raised
/// after each backup and each operation in [markActions]; null where the
/// desk has no data folder (tests unless they set one).

@ProviderFor(markStore)
final markStoreProvider = MarkStoreProvider._();

/// The two high-water marks (the data folder's and the second copy), raised
/// after each backup and each operation in [markActions]; null where the
/// desk has no data folder (tests unless they set one).

final class MarkStoreProvider
    extends $FunctionalProvider<MarkStore?, MarkStore?, MarkStore?>
    with $Provider<MarkStore?> {
  /// The two high-water marks (the data folder's and the second copy), raised
  /// after each backup and each operation in [markActions]; null where the
  /// desk has no data folder (tests unless they set one).
  MarkStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'markStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$markStoreHash();

  @$internal
  @override
  $ProviderElement<MarkStore?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MarkStore? create(Ref ref) {
    return markStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MarkStore? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MarkStore?>(value),
    );
  }
}

String _$markStoreHash() => r'7193496d65cb87ca9a1767eaa7f043e9e083286c';
