import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_repository.dart';
import '../theme/theme.dart';
import 'brand_wordmark.dart';

/// The lodging's wordmark on the desk ([BrandWordmark]), its name read from
/// settings. Falls back to "[LODGING NAME]" until first-run setup sets the
/// name.
class LodgingWordmark extends ConsumerWidget {
  const LodgingWordmark({
    super.key,
    this.size = WordmarkSize.sidebar,
    this.onDark = true,
  });

  final WordmarkSize size;
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => BrandWordmark(
    name: ref.watch(lodgingNameProvider).value ?? '',
    size: size,
    onDark: onDark,
  );
}
