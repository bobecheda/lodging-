import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/auth/permissions.dart';
import '../../core/auth/session.dart';
import '../../core/auth/user_account.dart';
import '../../core/clock/nairobi.dart';
import '../../core/settings/settings_repository.dart';
import '../../core/sync/outbox_status.dart';
import '../../features/auth/presentation/idle_lock.dart';
import '../../features/shifts/presentation/shift_providers.dart';
import '../gate.dart';
import '../theme/theme.dart';
import '../widgets/brand.dart';

part 'desk_shell.g.dart';

/// A sidebar destination.
class NavItem {
  const NavItem({
    required this.route,
    required this.label,
    required this.icon,
    this.permissions = const {},
    this.setup = false,
  });

  final String route;
  final String label;
  final IconData icon;

  /// Shown to users with any of these (none: everyone). The router enforces
  /// the same through `Routes.permissions`.
  final Set<Permission> permissions;

  /// Listed under "SETUP · OWNER ONLY".
  final bool setup;

  bool visibleTo(UserAccount? user) =>
      permissions.isEmpty ||
      (user != null && permissions.any((p) => can(user, p)));
}

/// Sidebar destinations. Only screens that exist are listed; each story
/// adds its own entry.
@Riverpod(keepAlive: true)
List<NavItem> deskNavItems(Ref ref) => const [
  NavItem(
    route: Routes.home,
    label: 'Bed board',
    icon: Icons.grid_view_rounded,
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
    permissions: {Permission.editPrices, Permission.editSettings},
    setup: true,
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
    final desk = items.where((i) => !i.setup).toList();
    final setup = items.where((i) => i.setup).toList();

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
          BrandHeader(
            lodgingName: ref.watch(lodgingNameProvider).value,
            subtitle: 'Front desk',
          ),
          const SizedBox(height: Space.x28),
          Expanded(
            child: ListView(
              children: [
                for (final item in desk) _NavTile(item, location),
                if (setup.isNotEmpty) ...[
                  const SizedBox(height: Space.x20),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.x12,
                      vertical: Space.x8,
                    ),
                    child: Text(
                      'SETUP · OWNER ONLY',
                      key: const ValueKey('shell.setupGroup'),
                      style: t.capsLabel.copyWith(color: c.navMuted),
                    ),
                  ),
                  for (final item in setup) _NavTile(item, location),
                ],
              ],
            ),
          ),
          const _SyncPill(),
          const SizedBox(height: Space.x16),
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

class _NavTile extends StatelessWidget {
  const _NavTile(this.item, this.location);

  final NavItem item;
  final String location;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final isActive =
        location == item.route || location.startsWith('${item.route}/');
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x4),
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
                      item.label,
                      style: isActive
                          ? t.nav.copyWith(
                              color: c.white,
                              fontWeight: FontWeight.w700,
                            )
                          : t.nav,
                    ),
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

class _UserBlock extends ConsumerWidget {
  const _UserBlock(this.user);

  final UserAccount user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final shift = ref.watch(currentShiftProvider).value;
    final role = switch (user.role) {
      Role.admin => 'Owner · admin',
      Role.receptionist =>
        shift?.userId == user.id
            ? 'Receptionist · shift since ${formatTime(shift!.openedAt)}'
            : 'Receptionist',
    };
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
