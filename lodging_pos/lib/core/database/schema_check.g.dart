// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schema_check.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Debug builds only: null when the database file matches this build (and
/// always null in release, on web, or where no in-memory database exists).

@ProviderFor(schemaDrift)
final schemaDriftProvider = SchemaDriftProvider._();

/// Debug builds only: null when the database file matches this build (and
/// always null in release, on web, or where no in-memory database exists).

final class SchemaDriftProvider
    extends
        $FunctionalProvider<
          AsyncValue<SchemaDrift?>,
          SchemaDrift?,
          FutureOr<SchemaDrift?>
        >
    with $FutureModifier<SchemaDrift?>, $FutureProvider<SchemaDrift?> {
  /// Debug builds only: null when the database file matches this build (and
  /// always null in release, on web, or where no in-memory database exists).
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

String _$schemaDriftHash() => r'353dbf9414c1dc1b6a58d0ebc27eddfd92075db2';

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
