import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The wordmark itself (docs/design.md, "Brand"): [name] in Pirata One with
/// a gold offset shadow, and "Lodging" under it. On marine by default
/// ([onDark]). The desk's [LodgingWordmark] reads the name from settings;
/// the owner's phone passes the one it loaded.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    required this.name,
    this.size = WordmarkSize.topBar,
    this.onDark = true,
    this.showWord = true,
  });

  /// The lodging's name; "[LODGING NAME]" while it's empty.
  final String name;
  final WordmarkSize size;
  final bool onDark;

  /// "Lodging" under the name; the top bar shows the name alone, on one
  /// line.
  final bool showWord;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final style = WordmarkStyle.of(c, size, onDark: onDark);
    final shown = name.trim().isEmpty ? '[LODGING NAME]' : name.trim();
    return Semantics(
      key: const ValueKey('brand.wordmark'),
      header: true,
      label: '$shown Lodging',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            shown,
            key: const ValueKey('brand.name'),
            maxLines: showWord ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: style.name,
          ),
          if (showWord) ...[
            SizedBox(height: style.gap),
            Text('Lodging', style: style.word),
          ],
        ],
      ),
    );
  }
}
