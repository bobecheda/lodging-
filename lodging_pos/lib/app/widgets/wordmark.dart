import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_repository.dart';
import '../theme/theme.dart';

/// The lodging's wordmark (docs/design.md, "Brand"): its name from settings
/// in Pirata One with a gold offset shadow, and "Lodging" under it. On
/// marine by default ([onDark]). Falls back to "[LODGING NAME]" until
/// first-run setup sets the name.
class LodgingWordmark extends ConsumerWidget {
  const LodgingWordmark({
    super.key,
    this.size = WordmarkSize.sidebar,
    this.onDark = true,
  });

  final WordmarkSize size;
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final style = WordmarkStyle.of(c, size, onDark: onDark);
    final stored = ref.watch(lodgingNameProvider).value?.trim() ?? '';
    final name = stored.isEmpty ? '[LODGING NAME]' : stored;
    return Semantics(
      key: const ValueKey('brand.wordmark'),
      header: true,
      label: '$name Lodging',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            key: const ValueKey('brand.name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style.name,
          ),
          SizedBox(height: style.gap),
          Text('Lodging', style: style.word),
        ],
      ),
    );
  }
}
