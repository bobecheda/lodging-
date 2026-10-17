// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schema_check.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Null when the database file matches this build (always null on web,
/// which has no local database).

@ProviderFor(schemaDrift)
final schemaDriftProvider = SchemaDriftProvider._();

/// Null when the database file matches this build (always null on web,
/// which has no local database).

final class SchemaDriftProvider
    extends
        $FunctionalProvider<
          AsyncValue<SchemaDrift?>,
          SchemaDrift?,
          FutureOr<SchemaDrift?>
        >
    with $FutureModifier<SchemaDrift?>, $FutureProvider<SchemaDrift?> {
  /// Null when the database file matches this build (always null on web,
  /// which has no local database).
  SchemaDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'schemaDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$schemaDriftHash();

  @$internal
  @override
  $FutureProviderElement<SchemaDrift?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SchemaDrift?> create(Ref ref) {
    return schemaDrift(ref);
  }
}

String _$schemaDriftHash() => r'513636c573f76df077882cabf6329d867fb77524';

/// Whether the mismatch screen may offer a reset: debug builds only. A
/// release build never throws data away; it shows an error instead.

@ProviderFor(canResetDatabase)
final canResetDatabaseProvider = CanResetDatabaseProvider._();

/// Whether the mismatch screen may offer a reset: debug builds only. A
/// release build never throws data away; it shows an error instead.

final class CanResetDatabaseProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the mismatch screen may offer a reset: debug builds only. A
  /// release build never throws data away; it shows an error instead.
  CanResetDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'canResetDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$canResetDatabaseHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return canResetDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$canResetDatabaseHash() => r'6ac8871e68ec400b9c679bdc1ec84c8060a18dbc';

/// Closes the database, renames its file to a timestamped `.bak` next to it
/// (kept, not deleted) and reopens a fresh one. Returns the backup's path.
/// Overridden in tests, which use in-memory databases.

@ProviderFor(resetTestDatabase)
final resetTestDatabaseProvider = ResetTestDatabaseProvider._();

/// Closes the database, renames its file to a timestamped `.bak` next to it
/// (kept, not deleted) and reopens a fresh one. Returns the backup's path.
/// Overridden in tests, which use in-memory databases.

final class ResetTestDatabaseProvider
    extends
        $FunctionalProvider<
          Future<String> Function(),
          Future<String> Function(),
          Future<String> Function()
        >
    with $Provider<Future<String> Function()> {
  /// Closes the database, renames its file to a timestamped `.bak` next to it
  /// (kept, not deleted) and reopens a fresh one. Returns the backup's path.
  /// Overridden in tests, which use in-memory databases.
  ResetTestDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'resetTestDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$resetTestDatabaseHash();

  @$internal
  @override
  $ProviderElement<Future<String> Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Future<String> Function() create(Ref ref) {
    return resetTestDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Future<String> Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Future<String> Function()>(value),
    );
  }
}

String _$resetTestDatabaseHash() => r'c33c07b5a673ae98c8ded1a7400a98e9d340d84d';
