// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_writer.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(auditWriter)
final auditWriterProvider = AuditWriterProvider._();

final class AuditWriterProvider
    extends $FunctionalProvider<AuditWriter, AuditWriter, AuditWriter>
    with $Provider<AuditWriter> {
  AuditWriterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'auditWriterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$auditWriterHash();

  @$internal
  @override
  $ProviderElement<AuditWriter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AuditWriter create(Ref ref) {
    return auditWriter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuditWriter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuditWriter>(value),
    );
  }
}

String _$auditWriterHash() => r'73e08a2b730a604af999b0d34c4b13997bac0447';
