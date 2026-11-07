import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/database/database_provider.dart';
import '../data/voids_repository.dart';

part 'voids_providers.g.dart';

@Riverpod(keepAlive: true)
VoidsRepository voidsRepository(Ref ref) => VoidsRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
);

/// One payment's receipt as the Voids screen shows it, watched: a void
/// shows at once.
@riverpod
Stream<VoidView> voidView(Ref ref, String paymentId) =>
    ref.watch(voidsRepositoryProvider).watchView(paymentId);
