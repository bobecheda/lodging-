part of 'desk_shell.dart';

// ── The drawer ─────────────────────────────────────────────────────────

/// Opens the menu drawer (brief, "Shell states"): 304 px from the left over
/// the scrim, the same destinations as the tabs, groups as plain sections,
/// the status, the user and Lock screen at the foot. Closes on X, the
/// scrim, Escape or choosing a page; focus stays inside while it's open.
/// Returns the chosen route.
Future<String?> showNavDrawer(
  BuildContext context, {
  required List<NavEntry> entries,
  required String? active,
  required UserAccount? user,
}) {
  final c = LodgingColors.of(context);
  final m = LodgingMotion.of(context);
  final router = GoRouter.of(context);
  return Navigator.of(context).push(
    ShellOverlayRoute<String>(
      label: 'Close the menu',
      scrim: c.scrim,
      inDuration: m.drawerIn.duration,
      outDuration: m.drawerOut.duration,
      scrimDuration: m.scrim.duration,
      transition: slideFrom(-1, m.drawerIn, m.drawerOut),
      builder: (context) => Align(
        alignment: Alignment.centerLeft,
        child: _Drawer(
          entries: entries,
          active: active,
          user: user,
          router: router,
        ),
      ),
    ),
  );
}

class _Drawer extends ConsumerWidget {
  const _Drawer({
    required this.entries,
    required this.active,
    required this.user,
    required this.router,
  });

  final List<NavEntry> entries;
  final String? active;
  final UserAccount? user;
  final GoRouter router;

  ShellMenuRow _row(WidgetRef ref, NavItem i) => ShellMenuRow(
    key: ValueKey('nav.${i.route}'),
    icon: i.icon,
    label: i.labelFor(user),
    active: i.route == active,
    badge: _badgeCount(ref, user, i.badge),
    value: i.route,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = this.user;
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    final status =
        ref.watch(syncStatusProvider).value ??
        const SyncStatus(phase: SyncPhase.notConfigured);
    final (_, tone) = syncBarText(status, pending: pending);
    final statusLine = syncPillText(
      status,
      pending: pending,
      now: ref.watch(clockProvider).now(),
    );
    void choose(String route) => Navigator.of(context).pop(route);

    Widget row(ShellMenuRow r, VoidCallback onTap, {bool autofocus = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _MenuRow(
            row: r,
            height: Sizes.drawerRow,
            drawer: true,
            autofocus: autofocus,
            onTap: onTap,
          ),
        );

    final links = [
      for (final e in entries)
        if (e case NavLink(:final item)) item,
    ];
    final groups = [
      for (final e in entries)
        if (e case NavMenu()) e,
    ];
    final userRows = user == null
        ? const <ShellMenuRow>[]
        : userMenuRows(ref, user);

    return Container(
      key: const ValueKey('shell.drawer'),
      width: Sizes.drawerWidth,
      height: double.infinity,
      decoration: BoxDecoration(
        color: c.white,
        border: Border(right: BorderSide(color: c.line)),
        boxShadow: [
          BoxShadow(
            color: c.ink.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x24,
                Space.x12,
                Space.x12,
                Space.x8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _Brand(
                      subtitle: user == null ? '' : roleSubtitle(user.role),
                    ),
                  ),
                  _IconButton(
                    key: const ValueKey('shell.drawer.close'),
                    icon: LucideIcons.x,
                    tooltip: 'Close the menu',
                    background: null,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // A short list, all built (not lazy), scrolling only when the
            // window is short.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Space.x12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, item) in links.indexed)
                      row(
                        _row(ref, item),
                        () => choose(item.route),
                        autofocus: i == 0,
                      ),
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.x12,
                          Space.x16,
                          Space.x12,
                          Space.x6,
                        ),
                        child: Text(
                          g.group.label,
                          style: t.meta.copyWith(color: c.muted),
                        ),
                      ),
                      for (final item in g.items)
                        row(_row(ref, item), () => choose(item.route)),
                    ],
                  ],
                ),
              ),
            ),
            Container(height: 1, color: c.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x12,
                Space.x16,
                Space.x12,
                Space.x16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x12),
                    child: Row(
                      children: [
                        Container(
                          width: Space.x8,
                          height: Space.x8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: switch (tone) {
                              SyncBarTone.online => c.green,
                              SyncBarTone.muted => c.muted,
                              SyncBarTone.warning => c.butterText,
                              SyncBarTone.problem => c.redText,
                            },
                          ),
                        ),
                        const SizedBox(width: Space.x8),
                        Expanded(
                          child: Text(
                            statusLine,
                            key: const ValueKey('shell.drawer.status'),
                            style: t.meta.copyWith(
                              color: switch (tone) {
                                SyncBarTone.warning => c.butterText,
                                SyncBarTone.problem => c.redText,
                                _ => c.inkSoft,
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (user != null) ...[
                    const SizedBox(height: Space.x16),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.x12,
                      ),
                      child: Row(
                        children: [
                          Avatar(user),
                          const SizedBox(width: Space.x12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user.fullName, style: t.secondaryMedium),
                                Text(
                                  _userLine(ref, user),
                                  style: t.meta.copyWith(color: c.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.x8),
                    for (final r in userRows)
                      row(r, () {
                        Navigator.of(context).pop();
                        actOnUserRow(router, r.value);
                      }),
                    const SizedBox(height: Space.x8),
                    FocusRing(
                      radius: Radii.control,
                      child: OutlinedButton(
                        key: const ValueKey('shell.drawer.lock'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          ref.read(idleLockProvider.notifier).lockNow();
                        },
                        child: const Text('Lock screen'),
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.x8),
                  const VersionFooter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
