import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/app_version.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session.dart';
import '../../core/auth/user_account.dart';
import '../../core/clock/clock.dart';
import '../../core/clock/nairobi.dart';
import '../../core/settings/settings_repository.dart';
import '../../core/sync/outbox_status.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/sync/sync_status_text.dart';
import '../../features/auth/presentation/change_my_password_dialog.dart';
import '../../features/auth/presentation/idle_lock.dart';
import '../../features/backup/domain/backup.dart';
import '../../features/backup/presentation/backup_providers.dart';
import '../../features/price_requests/presentation/price_requests_providers.dart';
import '../../features/refunds/presentation/refunds_providers.dart';
import '../../features/shifts/presentation/shift_providers.dart';
import '../../features/sync/presentation/sync_panel.dart';
import '../gate.dart';
import '../theme/theme.dart';
import '../widgets/focus_ring.dart';
import '../widgets/overlay_route.dart';
import '../widgets/wordmark.dart';
import 'shell_layout.dart';

part 'desk_shell.g.dart';
part 'nav_drawer.dart';
part 'shell_menus.dart';
part 'top_bar.dart';

/// A desk destination: a top tab, a row in a tab's menu, or a drawer row.
class NavItem {
  const NavItem({
    required this.route,
    required this.label,
    required this.icon,
    this.permissions = const {},
    this.group,
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

  /// Listed in a tab's menu ([NavGroup]) rather than as a tab of its own.
  final NavGroup? group;

  bool visibleTo(UserAccount? user) =>
      permissions.isEmpty ||
      (user != null && permissions.any((p) => can(user, p)));
}

/// Rarely used pages, gathered under one tab with a menu (brief, "Desk
/// navigation"); a section of the drawer.
enum NavGroup {
  /// The supervisor's setup pages. The owner's few (Prices, Staff) are tabs
  /// of their own.
  setup('Setup', LucideIcons.slidersHorizontal),

  /// Shifts and Voids, until Cash takes over Shifts (PR 7) and voiding
  /// moves onto the receipt (PR 8). Temporary: removed in PR 8.
  more('More', LucideIcons.ellipsis);

  const NavGroup(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// A live count beside a destination.
enum NavBadge {
  /// Approved refunds not yet paid (AD-7).
  refundsToPay,

  /// Price requests waiting for the owner; shown to the owner only.
  priceRequests,

  /// Cash reviews awaiting a decision this user may make (B3).
  cashReviews,
}

/// The desk's destinations, in tab order. Only screens that exist are
/// listed; each story adds its own entry.
@Riverpod(keepAlive: true)
List<NavItem> deskNavItems(Ref ref) => const [
  NavItem(
    route: Routes.today,
    label: 'Today',
    icon: LucideIcons.house,
    permissions: {Permission.viewBusinessDashboard},
  ),
  NavItem(
    route: Routes.home,
    label: 'Beds',
    icon: LucideIcons.bed,
    permissions: {Permission.checkIn},
  ),
  NavItem(
    route: Routes.receipts,
    label: 'Receipts',
    icon: LucideIcons.receipt,
    permissions: {Permission.printReceipts},
  ),
  NavItem(
    route: Routes.guests,
    label: 'Guests',
    icon: LucideIcons.users,
    permissions: {Permission.registerGuests},
  ),
  NavItem(
    route: Routes.refunds,
    label: 'Refunds',
    icon: LucideIcons.rotateCcw,
    permissions: {Permission.payRefund},
    badge: NavBadge.refundsToPay,
  ),
  NavItem(
    route: Routes.cash,
    label: 'Cash',
    icon: LucideIcons.banknote,
    permissions: {Permission.viewShiftTotals},
    badge: NavBadge.cashReviews,
  ),
  NavItem(
    route: Routes.adminRooms,
    label: 'Rooms & beds',
    icon: LucideIcons.house,
    permissions: {Permission.manageRooms},
    group: NavGroup.setup,
  ),
  NavItem(
    route: Routes.adminPrices,
    label: 'Prices & settings',
    icon: LucideIcons.slidersHorizontal,
    permissions: {
      Permission.editPrices,
      Permission.editSettings,
      Permission.manageBackups,
    },
    group: NavGroup.setup,
    shortLabel: 'Prices',
    fullLabelNeeds: {Permission.editSettings},
    badge: NavBadge.priceRequests,
  ),
  NavItem(
    route: Routes.adminStaff,
    label: 'Staff',
    icon: LucideIcons.users,
    permissions: {
      Permission.manageUsers,
      Permission.manageHousekeepers,
      Permission.manageSupervisors,
    },
    group: NavGroup.setup,
  ),
  NavItem(
    route: Routes.shifts,
    label: 'Shifts',
    icon: LucideIcons.clock,
    permissions: {Permission.viewShiftTotals},
    group: NavGroup.more,
  ),
  NavItem(
    route: Routes.voids,
    label: 'Voids',
    icon: LucideIcons.ban,
    permissions: {Permission.voidRecords},
    group: NavGroup.more,
  ),
];

/// A tab: one destination, or a group's menu.
sealed class NavEntry {
  const NavEntry();
}

final class NavLink extends NavEntry {
  const NavLink(this.item);
  final NavItem item;
}

final class NavMenu extends NavEntry {
  const NavMenu(this.group, this.items);
  final NavGroup group;
  final List<NavItem> items;
}

/// [user]'s tabs, in order: their destinations, then More ▾, then Setup ▾.
/// The setup group is the supervisor's (`manageRooms`); for anyone else
/// its pages they may open are tabs of their own (the owner's Prices and
/// Staff).
List<NavEntry> navEntriesFor(UserAccount? user, List<NavItem> items) {
  final visible = items.where((i) => i.visibleTo(user)).toList();
  final setupGrouped = user != null && can(user, Permission.manageRooms);
  NavGroup? groupOf(NavItem i) =>
      i.group == NavGroup.setup && !setupGrouped ? null : i.group;
  return [
    for (final i in visible)
      if (groupOf(i) == null) NavLink(i),
    for (final g in const [NavGroup.more, NavGroup.setup])
      if (visible.where((i) => groupOf(i) == g).toList() case final rows
          when rows.isNotEmpty)
        NavMenu(g, rows),
  ];
}

/// Pages that open from a tab's screen and belong to it: check-in is the
/// bed board's.
const navFlows = {Routes.checkIn: Routes.home};

/// The role subtitle under the wordmark (brief, "Desk navigation").
String roleSubtitle(Role role) => switch (role) {
  Role.owner => 'Owner',
  Role.supervisor => 'Supervisor',
  Role.receptionist => 'Front desk',
};

/// The desk layout (docs/design-system.md, "Desk navigation"): a 64 px
/// white top bar with icon tabs, and the page under it on `surface`,
/// capped at 1280 px wide and centred. When the tabs don't fit, they
/// collapse into a menu button that opens the drawer.
class DeskShell extends ConsumerWidget {
  const DeskShell({super.key, required this.location, required this.child});

  /// The current route, to mark its tab.
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final user = ref.watch(sessionProvider);
    final entries = navEntriesFor(user, ref.watch(deskNavItemsProvider));
    return Scaffold(
      backgroundColor: c.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TopBar(location: location, entries: entries, user: user),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: math.min(box.maxWidth, Sizes.contentMax),
                  height: box.maxHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.x28,
                      vertical: Space.x24,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Badges ─────────────────────────────────────────────────────────────

int _badgeCount(WidgetRef ref, UserAccount? user, NavBadge? badge) =>
    switch (badge) {
      null => 0,
      NavBadge.refundsToPay => ref.watch(refundsToPayProvider).value ?? 0,
      NavBadge.priceRequests =>
        user != null && can(user, Permission.decidePriceChange)
            ? ref.watch(waitingPriceRequestsProvider).value?.length ?? 0
            : 0,
      NavBadge.cashReviews => ref.watch(cashReviewsToDecideProvider).value ?? 0,
    };

int _entryCount(WidgetRef ref, UserAccount? user, NavEntry e) => switch (e) {
  NavLink(:final item) => _badgeCount(ref, user, item.badge),
  NavMenu(:final items) => items.fold(
    0,
    (n, i) => n + _badgeCount(ref, user, i.badge),
  ),
};

/// A small butter count; nothing at zero. The number cross-fades when it
/// changes.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});

  final int count;

  /// Its width for [count] in [style] (no badge at zero).
  static double widthOf(int count, TextStyle style, TextScaler scaler) =>
      count == 0 ? 0 : _textWidth('$count', style, scaler) + 2 * 7;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final m = LodgingMotion.of(context);
    return AnimatedSwitcher(
      duration: m.count.duration,
      child: count == 0
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey(count),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: c.butter,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                '$count',
                style: t.meta.copyWith(color: c.butterText),
              ),
            ),
    );
  }
}

double _textWidth(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
