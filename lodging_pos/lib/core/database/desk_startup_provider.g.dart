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

/// Writes the high-water mark after each backup; null where the desk has
/// no data folder (tests unless they set one).

@ProviderFor(markWriter)
final markWriterProvider = MarkWriterProvider._();

/// Writes the high-water mark after each backup; null where the desk has
/// no data folder (tests unless they set one).

final class MarkWriterProvider
    extends
        $FunctionalProvider<
          Future<void> Function(HighWaterMark mark)?,
          Future<void> Function(HighWaterMark mark)?,
          Future<void> Function(HighWaterMark mark)?
        >
    with $Provider<Future<void> Function(HighWaterMark mark)?> {
  /// Writes the high-water mark after each backup; null where the desk has
  /// no data folder (tests unless they set one).
  MarkWriterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'markWriterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$markWriterHash();

  @$internal
  @override
  $ProviderElement<Future<void> Function(HighWaterMark mark)?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Future<void> Function(HighWaterMark mark)? create(Ref ref) {
    return markWriter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Future<void> Function(HighWaterMark mark)? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<Future<void> Function(HighWaterMark mark)?>(value),
    );
  }
}

String _$markWriterHash() => r'8fd73cdad46cdadb0cff2eb56d454d36c516f7b8';
