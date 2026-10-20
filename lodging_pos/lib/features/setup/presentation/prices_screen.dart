import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../backup/presentation/backup_providers.dart';
import '../../backup/presentation/backups_card.dart';
import 'widgets/category_prices_card.dart';
import 'widgets/settings_card.dart';

/// AD-3 "Prices and settings": bed category prices beside the lodging's
/// rules and receipt settings (artboard "Setup — prices and settings"), and
/// under them the desk's Backups card.
class PricesScreen extends ConsumerWidget {
  const PricesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final backups =
        user != null &&
        can(user, Permission.manageBackups) &&
        ref.watch(backupsProvider.select((s) => s.enabled));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Prices and settings', style: t.pageTitle),
        ),
        const SizedBox(height: Space.x20),
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(flex: 5, child: CategoryPricesCard()),
                const SizedBox(width: Space.x24),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SettingsCard(),
                      if (backups) ...[
                        const SizedBox(height: Space.x24),
                        const BackupsCard(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
