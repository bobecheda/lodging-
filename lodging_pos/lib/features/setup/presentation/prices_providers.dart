import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audit/audit_writer.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/prices_repository.dart';
import '../domain/prices_settings.dart';

part 'prices_providers.g.dart';

@Riverpod(keepAlive: true)
PricesRepository pricesRepository(Ref ref) => PricesRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(auditWriterProvider),
  cloud: ref.watch(cloudWritesProvider),
);

/// Categories in sort order with their active beds. Invalidate after a write.
@riverpod
Future<List<CategoryUsage>> categoryUsage(Ref ref) =>
    ref.watch(pricesRepositoryProvider).categories();

/// The settings form as stored. Invalidate after saving.
@riverpod
Future<SettingsInput> settingsForm(Ref ref) =>
    ref.watch(pricesRepositoryProvider).settings();

/// The next receipt number on this device, for the prefix preview.
@riverpod
Future<int> nextReceiptNumber(Ref ref) =>
    ref.watch(pricesRepositoryProvider).nextReceiptNumber();
