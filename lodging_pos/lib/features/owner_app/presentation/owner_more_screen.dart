import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../domain/owner_more.dart';
import 'owner_app.dart';
import 'owner_providers.dart';

/// More (Figma "07 More"): Shifts, the Audit trail, Reports (coming next)
/// and Staff, all read-only; who is signed in, Change password and Sign
/// out.
class OwnerMoreScreen extends ConsumerWidget {
  const OwnerMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final signedIn = ref.watch(ownerSessionProvider).value;
    final today = ref.watch(ownerTodayDataProvider).value?.today;
    final now = ref.watch(ownerClockProvider).now();
    return ListView(
      key: const ValueKey('owner.more'),
      padding: const EdgeInsets.all(Space.x16),
      children: [
        Semantics(header: true, child: Text('More', style: t.pageTitle)),
        const SizedBox(height: Space.x12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _MenuRow(
                keyName: 'shifts',
                icon: Icons.account_balance_wallet_outlined,
                title: 'Shifts',
                subtitle: 'Who worked, takings and cash counts',
                onTap: () => context.go(OwnerRoutes.shifts),
              ),
              Divider(height: 1, color: c.lineSoft),
              _MenuRow(
                keyName: 'audit',
                icon: Icons.history_rounded,
                title: 'Audit trail',
                subtitle: 'Every action at the desk: who, what, when',
                onTap: () => context.go(OwnerRoutes.audit),
              ),
              Divider(height: 1, color: c.lineSoft),
              const _MenuRow(
                keyName: 'reports',
                icon: Icons.bar_chart_rounded,
                title: 'Reports',
                subtitle: 'Monthly report (PDF) · coming next',
                onTap: null,
              ),
              Divider(height: 1, color: c.lineSoft),
              _MenuRow(
                keyName: 'staff',
                icon: Icons.people_outline_rounded,
                title: 'Staff',
                subtitle: 'Supervisors and receptionists',
                onTap: () => context.go(OwnerRoutes.staff),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.x12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Space.x20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('SIGNED IN AS', style: t.cardHeading),
                const SizedBox(height: Space.x12),
                Text(
                  [
                    'Owner',
                    if (today != null && today.lodgingName.isNotEmpty)
                      today.lodgingName,
                  ].join(' · '),
                  style: t.bodyStrong,
                ),
                Text(
                  signedIn?.email ?? '',
                  key: const ValueKey('owner.more.email'),
                  style: t.body.copyWith(color: c.inkSoft),
                ),
                const SizedBox(height: Space.x8),
                Text(
                  today == null ? '' : deskSyncedLine(today.desks, now),
                  key: const ValueKey('owner.more.desk'),
                  style: t.small.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.x12),
        AppButton.secondary(
          key: const ValueKey('owner.changePassword'),
          label: 'Change password',
          icon: Icons.key_outlined,
          large: true,
          onPressed: () => context.go(OwnerRoutes.password),
        ),
        const SizedBox(height: Space.x12),
        AppButton.secondary(
          key: const ValueKey('owner.signOut'),
          label: 'Sign out',
          icon: Icons.logout_rounded,
          large: true,
          onPressed: () => ref.read(ownerSessionProvider.notifier).signOut(),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.keyName,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String keyName;
  final IconData icon;
  final String title;
  final String subtitle;

  /// Null: shown, not yet available.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final ink = onTap == null ? c.muted : c.ink;
    return InkWell(
      key: ValueKey('owner.more.$keyName'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.x14),
        child: Row(
          children: [
            Container(
              width: Sizes.target - 4,
              height: Sizes.target - 4,
              decoration: BoxDecoration(
                color: c.marineTint,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Icon(icon, color: onTap == null ? c.muted : c.marine),
            ),
            const SizedBox(width: Space.x12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.bodyStrong.copyWith(color: ink)),
                  Text(subtitle, style: t.small.copyWith(color: c.muted)),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: c.muted),
          ],
        ),
      ),
    );
  }
}
