import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session.dart';
import '../../core/settings/settings_repository.dart';
import '../theme/theme.dart';
import 'brand.dart';

/// Marine bar with the brand on the left and "Signed in as … / Sign out" on
/// the right (artboard "Open or resume shift").
class GateTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const GateTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final name = ref.watch(lodgingNameProvider).value;
    return Container(
      height: preferredSize.height,
      color: c.marine,
      padding: const EdgeInsets.symmetric(horizontal: Space.x28),
      child: Row(
        children: [
          Expanded(child: BrandHeader(lodgingName: name)),
          if (user != null) ...[
            Text.rich(
              TextSpan(
                text: 'Signed in as ',
                style: t.body.copyWith(color: c.navMuted),
                children: [
                  TextSpan(
                    text: user.fullName,
                    style: t.bodyStrong.copyWith(color: c.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.x16),
            OutlinedButton(
              key: const ValueKey('topbar.signOut'),
              onPressed: () => ref.read(sessionProvider.notifier).signOut(),
              style: OutlinedButton.styleFrom(
                backgroundColor: c.marine,
                foregroundColor: c.white,
                side: BorderSide(color: c.navMuted),
                minimumSize: const Size(Sizes.target, Sizes.targetCompact),
              ),
              child: Text(
                'Sign out',
                style: t.bodyStrong.copyWith(color: c.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
