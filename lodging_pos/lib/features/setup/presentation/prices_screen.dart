import 'package:flutter/material.dart';

import '../../../app/theme/theme.dart';
import 'widgets/category_prices_card.dart';
import 'widgets/settings_card.dart';

/// AD-3 "Prices and settings": bed category prices beside the lodging's
/// rules and receipt settings (artboard "Setup — prices and settings").
class PricesScreen extends StatelessWidget {
  const PricesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Prices and settings', style: t.pageTitle),
        ),
        const SizedBox(height: Space.x20),
        const Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: CategoryPricesCard()),
                SizedBox(width: Space.x24),
                Expanded(flex: 4, child: SettingsCard()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
