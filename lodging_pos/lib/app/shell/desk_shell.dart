import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/auth/permissions.dart';
import '../../core/auth/session.dart';
import '../../core/auth/user_account.dart';
import '../../core/clock/clock.dart';
import '../../core/clock/nairobi.dart';
import '../../core/sync/outbox_status.dart';
import '../../features/auth/presentation/idle_lock.dart';
import '../../features/backup/domain/backup.dart';
import '../../features/backup/presentation/backup_providers.dart';
import '../../features/price_requests/presentation/price_requests_providers.dart';
import '../../features/refunds/presentation/refunds_providers.dart';
import '../../features/shifts/presentation/shift_providers.dart';
import '../gate.dart';
import '../theme/theme.dart';
import '../widgets/wordmark.dart';

part 'desk_shell.g.dart';

/// A sidebar destination.
class NavItem {
  const NavItem({
    required this.route,
    required this.label,
    required this.icon,
    this.permissions = const {},
    this.setup = false,
    this.shortLabel,
    this.fullLabelNeeds = const {},
    this.badge,
  });

  final String route;
  final String label;
  final IconData icon;

  /// The label for a user with none of [fullLabelNeeds], e.g. the owner's
  /// "Prices" (no settings) for "Prices & settings".
  final String? shortLabel;
  final Set<Permission> fullLabelNeeds;

  /// A count shown beside the label, e.g. refunds ready to pay.
  final NavBadge? badge;

  String labelFor(UserAccount? user) =>
      shortLabel != null &&
          user != null &&
          !fullLabelNeeds.any((p) => can(user, p))
      ? shortLabel!
      : label;

  /// Shown to users with any of these (none: everyone). The router enforces
  /// the same through `Routes.permissions`.
  final Set<Permission> permissions;

  /// Listed under "SETUP · SUPERVISOR" for the supervisor; the owner's few
  /// setup screens (Prices, Staff) are listed with the rest.
  final bool setup;

  bool visibleTo(UserAccount? user) =>
      permissions.isEmpty ||
      (user != null && permissions.any((p) => can(user, p)));
}

/// A live count beside a sidebar item.
enum NavBadge {
  /// Approved refunds not yet paid (AD-7).
  refundsToPay,

  /// Price requests waiting for the owner; shown to the owner only.
  priceRequests,
}

/// Sidebar destinations. Only screens that exist are listed; each story
/// adds its own entry.
@Riverpod(keepAlive: true)
List<NavItem> deskNavItems(Ref ref) => const [
  NavItem(
    route: Routes.today,
    label: 'Today',
    icon: Icons.today_outlined,
    permissions: {Permission.viewBusinessDashboard},
  ),
  NavItem(
    route: Routes.home,
    label: 'Bed board',
    icon: Icons.grid_view_rounded,
    permissions: {Permission.checkIn},
  ),
  NavItem(
    route: Routes.guests,
    label: 'Guests',
    icon: Icons.person_search_outlined,
    permissions: {Permission.registerGuests},
  ),
  NavItem(
    route: Routes.receipts,
    label: 'Receipts',
    icon: Icons.receipt_long_outlined,
    permissions: {Permission.printReceipts},
  ),
  NavItem(
    route: Routes.refunds,
    label: 'Refunds',
    icon: Icons.replay_rounded,
    permissions: {Permission.payRefund},
    badge: NavBadge.refundsToPay,
  ),
  NavItem(
    route: Routes.shifts,
    label: 'Shifts',
    icon: Icons.point_of_sale_outlined,
    permissions: {Permission.viewAllReports},
  ),
  NavItem(
    route: Routes.adminRooms,
    label: 'Rooms & beds',
    icon: Icons.bed_outlined,
    permissions: {Permission.manageRooms},
    setup: true,
  ),
  NavItem(
    route: Routes.adminPrices,
    label: 'Prices & settings',
    icon: Icons.sell_outlined,
    permissions: {
      Permission.editPrices,
      Permission.editSettings,
      Permission.manageBackups,
    },
    setup: true,
    shortLabel: 'Prices',
    fullLabelNeeds: {Permission.editSettings},
    badge: NavBadge.priceRequests,
  ),
  NavItem(
    route: Routes.adminStaff,
    label: 'Users & staff',
    icon: Icons.people_outline_rounded,
    permissions: {
      Permission.manageUsers,
      Permission.manageHousekeepers,
      Permission.manageSupervisors,
    },
    setup: true,
    shortLabel: 'Staff',
    fullLabelNeeds: {Permission.manageHousekeepers},
  ),
];

/// The desk layout (docs/design.md, "Desk shell"): a 232px marine sidebar
/// and the content area on `surface`.
class DeskShell extends ConsumerWidget {
  const DeskShell({super.key, required this.location, required this.child});

  /// The current route, to highlight its nav item.
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final items = ref
        .watch(deskNavItemsProvider)
        .where((i) => i.visibleTo(user));
    // The setup group is the supervisor's; the owner's setup screens sit
    // with the rest.
    final grouped = user != null && can(user, Permission.manageRooms);
    final desk = items.where((i) => !grouped || !i.setup).toList();
    final setup = items.where((i) => grouped && i.setup).toList();

    final sidebar = Container(
      width: Sizes.sidebarWidth,
      color: c.marine,
      padding: const EdgeInsets.fromLTRB(
        Space.x16,
        Space.x24,
        Space.x16,
        Space.x20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LodgingWordmark(),
          const SizedBox(height: Space.x6),
          Text('Front desk', style: t.small.copyWith(color: c.navMuted)),
          const SizedBox(height: Space.x16),
          // Every item built (not lazy), scrolling only if the desk's
          // warnings push it past a 768-high screen.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in desk) _NavTile(item, location, user),
                  if (setup.isNotEmpty) ...[
                    const SizedBox(height: Space.x10),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.x12,
                        vertical: Space.x6,
                      ),
                      child: Text(
                        'SETUP · SUPERVISOR',
                        key: const ValueKey('shell.setupGroup'),
                        style: t.capsLabel.copyWith(color: c.navMuted),
                      ),
                    ),
                    for (final item in setup) _NavTile(item, location, user),
                  ],
                ],
              ),
            ),
          ),
          const _BackupPill(),
          const _SyncPill(),
          const SizedBox(height: Space.x12),
          if (user != null) _UserBlock(user),
        ],
      ),
    );

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sidebar,
          Expanded(
            child: ColoredBox(
              color: c.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.x28,
                  vertical: Space.x24,
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends ConsumerWidget {
  const _NavTile(this.item, this.location, this.user);

  final NavItem item;
  final String location;
  final UserAccount? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final isActive =
        location == item.route || location.startsWith('${item.route}/');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: isActive,
        button: true,
        child: Material(
          color: isActive ? c.navActive : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.control),
          child: InkWell(
            key: ValueKey('nav.${item.route}'),
            borderRadius: BorderRadius.circular(Radii.control),
            onTap: isActive ? null : () => context.go(item.route),
            child: Container(
              constraints: const BoxConstraints(minHeight: Sizes.target),
              padding: const EdgeInsets.symmetric(horizontal: Space.x12),
              child: Row(
                children: [
                  if (isActive)
                    Container(
                      width: Space.x8,
                      height: Space.x8,
                      margin: const EdgeInsetsDirectional.only(end: Space.x10),
                      decoration: BoxDecoration(
                        color: c.butter,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(width: Space.x8 + Space.x10),
                  Expanded(
                    child: Text(
                      item.labelFor(user),
                      style: isActive
                          ? t.nav.copyWith(
                              color: c.white,
                              fontWeight: FontWeight.w700,
                            )
                          : t.nav,
                    ),
                  ),
                  if (item.badge == NavBadge.refundsToPay)
                    _CountBadge(
                      ref.watch(refundsToPayProvider).value ?? 0,
                      key: ValueKey('nav.badge.${item.route}'),
                    )
                  else if (item.badge == NavBadge.priceRequests &&
                      user != null &&
                      can(user!, Permission.decidePriceChange))
                    _CountBadge(
                      ref.watch(waitingPriceRequestsProvider).value?.length ??
                          0,
                      key: ValueKey('nav.badge.${item.route}'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small butter count beside a sidebar label; nothing at zero.
class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.x8, vertical: 1),
      decoration: BoxDecoration(
        color: c.butter,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text('$count', style: t.smallStrong.copyWith(color: c.butterText)),
    );
  }
}

/// Until sync exists (sprint 2), say so honestly and count what's waiting.
class _SyncPill extends ConsumerWidget {
  const _SyncPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final waiting = ref.watch(pendingChangesProvider).value;
    final count = waiting == null
        ? '…'
        : '$waiting ${waiting == 1 ? 'change' : 'changes'} waiting';
    return Container(
      key: const ValueKey('shell.syncPill'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x12,
        vertical: Space.x10,
      ),
      decoration: BoxDecoration(
        color: c.butter,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: c.butterText),
          const SizedBox(width: Space.x8),
          Expanded(
            child: Text(
              'Sync not set up · $count',
              style: t.smallStrong.copyWith(color: c.butterText),
            ),
          ),
        ],
      ),
    );
  }
}

/// Only when the main backup failed or yesterday and today have none
/// ([backupOverdue]); everyone sees it, so a receptionist can tell the
/// supervisor. A supervisor's tap opens the Backups card. A missing second copy is
/// never shown here.
class _BackupPill extends ConsumerWidget {
  const _BackupPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final status = ref.watch(backupsProvider);
    if (!status.overdueAt(ref.watch(clockProvider).now())) {
      return const SizedBox.shrink();
    }
    final user = ref.watch(sessionProvider);
    final canFix = user != null && can(user, Permission.manageBackups);
    final text = backupOverdueText(
      newest: status.newest?.takenAt,
      failed: status.lastFailure != null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x8),
      child: Material(
        color: c.butter,
        borderRadius: BorderRadius.circular(Radii.control),
        child: InkWell(
          key: const ValueKey('shell.backupPill'),
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: canFix ? () => context.go(Routes.adminPrices) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x12,
              vertical: Space.x10,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: c.butterText,
                ),
                const SizedBox(width: Space.x8),
                Expanded(
                  child: Text(
                    text,
                    style: t.smallStrong.copyWith(color: c.butterText),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserBlock extends ConsumerWidget {
  const _UserBlock(this.user);

  final UserAccount user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final shift = ref.watch(currentShiftProvider).value;
    final ownShift = shift != null && shift.userId == user.id;
    final role = [
      switch (user.role) {
        Role.owner => 'Owner',
        Role.supervisor => 'Supervisor',
        Role.receptionist => 'Receptionist',
      },
      if (ownShift) 'shift since ${formatTime(shift.openedAt)}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          user.fullName,
          key: const ValueKey('shell.userName'),
          style: t.bodyStrong.copyWith(color: c.white),
        ),
        Text(
          role,
          key: const ValueKey('shell.userRole'),
          style: t.small.copyWith(color: c.navMuted),
        ),
        const SizedBox(height: Space.x12),
        // FD-11: close your own shift (count the cash, then sign out).
        if (ownShift && can(user, Permission.closeShift)) ...[
          OutlinedButton.icon(
            key: const ValueKey('shell.closeShift'),
            onPressed: () => context.go(Routes.closeShift),
            icon: Icon(Icons.point_of_sale_outlined, size: 18, color: c.white),
            label: Text(
              'Close shift',
              style: t.bodyStrong.copyWith(color: c.white),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: c.marine,
              side: BorderSide(color: c.navMuted),
              minimumSize: const Size(Sizes.target, Sizes.targetCompact),
            ),
          ),
          const SizedBox(height: Space.x8),
        ],
        OutlinedButton.icon(
          key: const ValueKey('shell.lock'),
          onPressed: () => ref.read(idleLockProvider.notifier).lockNow(),
          icon: Icon(Icons.lock_outline_rounded, size: 18, color: c.white),
          label: Text(
            'Lock screen',
            style: t.bodyStrong.copyWith(color: c.white),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: c.marine,
            side: BorderSide(color: c.navMuted),
            minimumSize: const Size(Sizes.target, Sizes.targetCompact),
          ),
        ),
      ],
    );
  }
}
