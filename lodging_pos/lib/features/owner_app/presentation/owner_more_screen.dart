import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import 'owner_providers.dart';

/// More: the account and Sign out (Shifts, the audit trail, Staff and
/// Change password come in owner-app-3).
class OwnerMoreScreen extends ConsumerWidget {
  const OwnerMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final signedIn = ref.watch(ownerSessionProvider).value;
    return ListView(
      padding: const EdgeInsets.all(Space.x16),
      children: [
        Semantics(header: true, child: Text('More', style: t.pageTitle)),
        const SizedBox(height: Space.x16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Space.x20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('ACCOUNT', style: t.cardHeading),
                const SizedBox(height: Space.x12),
                Text(
                  signedIn?.email ?? '',
                  key: const ValueKey('owner.more.email'),
                  style: t.bodyStrong,
                ),
                Text(
                  'Owner · signed in on this phone until you sign out.',
                  style: t.small.copyWith(color: c.muted),
                ),
                const SizedBox(height: Space.x16),
                AppButton.secondary(
                  key: const ValueKey('owner.signOut'),
                  label: 'Sign out',
                  icon: Icons.logout_rounded,
                  onPressed: () =>
                      ref.read(ownerSessionProvider.notifier).signOut(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
