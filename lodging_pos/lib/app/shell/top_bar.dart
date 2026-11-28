part of 'desk_shell.dart';

// ── The top bar ────────────────────────────────────────────────────────

/// The light top bar (brief, "Desk navigation" and "Shell states"): the
/// wordmark and role, the tabs (or the menu button when they don't fit),
/// the Check in button, the backup and sync status, the user button and
/// Lock. It floats (story/ui-floating-nav): 12 px clear of the window's
/// top and sides, rounded, with a 1 px line border and a soft shadow, and
/// the page starts under it. It never moves; only the indicator slides
/// between tabs.
class TopBar extends ConsumerStatefulWidget {
  const TopBar({
    super.key,
    required this.location,
    required this.entries,
    required this.user,
  });

  final String location;
  final List<NavEntry> entries;
  final UserAccount? user;

  @override
  ConsumerState<TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<TopBar> {
  final _menuButton = FocusNode(debugLabel: 'shell.menu');
  final _tabNodes = <String, FocusNode>{};
  final _tabKeys = <String, GlobalKey>{};

  FocusNode _nodeFor(String id) =>
      _tabNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'tab.$id'));
  GlobalKey _keyFor(String id) => _tabKeys.putIfAbsent(id, GlobalKey.new);

  @override
  void dispose() {
    _menuButton.dispose();
    for (final n in _tabNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  String? get _active => activeRouteFor(widget.location, [
    for (final e in widget.entries)
      ...switch (e) {
        NavLink(:final item) => [item.route],
        NavMenu(:final items) => items.map((i) => i.route),
      },
  ], flows: navFlows);

  bool _isActive(NavEntry e) => switch (e) {
    NavLink(:final item) => item.route == _active,
    NavMenu(:final items) => items.any((i) => i.route == _active),
  };

  static String _entryId(NavEntry e) => switch (e) {
    NavLink(:final item) => item.route,
    NavMenu(:final group) => 'group.${group.name}',
  };

  String _entryLabel(NavEntry e) => switch (e) {
    NavLink(:final item) => item.labelFor(widget.user),
    NavMenu(:final group) => group.label,
  };

  void _go(String route) {
    if (route != widget.location) context.go(route);
  }

  Future<void> _openMenu(NavMenu menu) async {
    final id = _entryId(menu);
    final box = _keyFor(id).currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final router = GoRouter.of(context);
    final route = await showShellMenu<String>(
      context,
      anchor: anchor,
      label: '${menu.group.label} menu',
      rows: [
        for (final i in menu.items)
          ShellMenuRow(
            key: ValueKey('nav.${i.route}'),
            icon: i.icon,
            label: i.labelFor(widget.user),
            active: i.route == _active,
            badge: _badgeCount(ref, widget.user, i.badge),
            value: i.route,
          ),
      ],
    );
    if (!mounted) return;
    _nodeFor(id).requestFocus();
    if (route != null && route != widget.location) router.go(route);
  }

  Future<void> _openDrawer() async {
    final router = GoRouter.of(context);
    final route = await showNavDrawer(
      context,
      entries: widget.entries,
      active: _active,
      user: widget.user,
    );
    if (!mounted) return;
    _menuButton.requestFocus();
    if (route != null && route != widget.location) router.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final m = LodgingMotion.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final user = widget.user;
    final lodgingName = ref.watch(lodgingNameProvider).value ?? '';
    final subtitle = user == null ? '' : roleSubtitle(user.role);

    final tabWidths = [
      for (final e in widget.entries)
        topTabWidth(
          labelWidth: _textWidth(_entryLabel(e), t.secondaryMedium, scaler),
          badgeWidth: CountBadge.widthOf(
            _entryCount(ref, user, e),
            t.meta,
            scaler,
          ),
          menu: e is NavMenu,
        ),
    ];
    final canCheckIn = user != null && can(user, Permission.checkIn);
    final ctaLabelWidth = math.max(
      _textWidth(checkInLabel, t.bodyMedium, scaler),
      _textWidth(checkInHoverLabel, t.bodyMedium, scaler),
    );
    final cta = canCheckIn ? ctaWidth(labelWidth: ctaLabelWidth) : 0.0;
    final wordStyle = WordmarkStyle.of(c, WordmarkSize.topBar, onDark: false);
    // The name may be cut at 200 px (the wordmark's own ellipsis); the role
    // under it never is.
    final wordmarkWidth = math.max(
      math.min(
        200.0,
        _textWidth(
          lodgingName.trim().isEmpty ? '[LODGING NAME]' : lodgingName.trim(),
          wordStyle.name,
          scaler,
        ),
      ),
      _textWidth(subtitle, t.meta, scaler),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Sizes.topBarMargin,
        Sizes.topBarMargin,
        Sizes.topBarMargin,
        0,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          const pad = Space.x24;
          const inset = Sizes.topBarInset;
          // The wordmark sits 16 px in from the border: the bar's 8 px and 8
          // more, so it doesn't crowd the rounded corner.
          const brandInset = Space.x8;
          // Either side of the divider before the user.
          const split = Space.x16;
          final status = _StatusSlot.widthOf(ref, user, t, scaler);
          final userBlock = _UserButton.widthOf(ref, user, t, scaler);
          // After the tabs: Check in (or a gap), then status, divider, user,
          // Lock, with the name shown.
          final afterTabs = canCheckIn ? ctaGap + cta + ctaClear : pad;
          final trailing =
              afterTabs +
              status +
              split +
              1 +
              split +
              userBlock +
              Space.x12 +
              Sizes.target +
              inset;
          final nameWidth = user == null
              ? 0.0
              : _UserButton.nameWidthOf(ref, user, t, scaler);
          final layout = user == null
              ? BarLayout.full
              : barLayout(
                  barWidth: box.maxWidth,
                  leading: inset + brandInset + wordmarkWidth + pad,
                  tabWidths: tabWidths,
                  trailing: trailing,
                  nameWidth: nameWidth,
                );
          final collapsed = layout == BarLayout.folded;
          // Folded: the menu button, the wordmark, Check in, then the right
          // part without the name. Too narrow even so (768 with large text
          // or a backup warning): Check in keeps only its icon.
          final folded =
              inset +
              Sizes.target +
              Space.x8 +
              wordmarkWidth +
              pad +
              cta +
              ctaClear +
              status +
              split +
              1 +
              split +
              userBlock -
              nameWidth +
              Space.x12 +
              Sizes.target +
              inset;
          final iconOnly = collapsed && folded > box.maxWidth;
          final showName = layout == BarLayout.full;
          final tabsLeft = inset + brandInset + wordmarkWidth + pad;
          final activeIndex = widget.entries.indexWhere(_isActive);
          double tabX(int i) =>
              tabsLeft +
              tabWidths.take(i).fold(0.0, (a, b) => a + b) +
              tabSpacing * i;

          return Container(
            key: const ValueKey('shell.topBar'),
            height: Sizes.topBar,
            decoration: BoxDecoration(
              color: c.white,
              borderRadius: BorderRadius.circular(Radii.floatingBar),
              border: Border.all(color: c.line),
              boxShadow: LodgingShadows.floatingBar(c),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: inset),
                    child: Row(
                      children: [
                        if (collapsed) ...[
                          _IconButton(
                            key: const ValueKey('shell.menu'),
                            focusNode: _menuButton,
                            icon: LucideIcons.menu,
                            tooltip: 'Menu',
                            background: null,
                            onTap: _openDrawer,
                          ),
                          const SizedBox(width: Space.x8),
                        ] else
                          const SizedBox(width: brandInset),
                        SizedBox(
                          width: wordmarkWidth,
                          child: _Brand(subtitle: subtitle),
                        ),
                        const SizedBox(width: pad),
                        if (!collapsed)
                          for (final (i, e) in widget.entries.indexed) ...[
                            if (i > 0) const SizedBox(width: tabSpacing),
                            _TopTab(
                              key: ValueKey('nav.${_entryId(e)}'),
                              anchorKey: _keyFor(_entryId(e)),
                              focusNode: _nodeFor(_entryId(e)),
                              width: tabWidths[i],
                              label: _entryLabel(e),
                              icon: switch (e) {
                                NavLink(:final item) => item.icon,
                                NavMenu(:final group) => group.icon,
                              },
                              active: _isActive(e),
                              badge: _entryCount(ref, user, e),
                              badgeKey: switch (e) {
                                NavLink(:final item) => ValueKey(
                                  'nav.badge.${item.route}',
                                ),
                                NavMenu(:final group) => ValueKey(
                                  'nav.badge.group.${group.name}',
                                ),
                              },
                              menu: e is NavMenu,
                              onTap: switch (e) {
                                NavLink(:final item) => () => _go(item.route),
                                NavMenu() => () => _openMenu(e),
                              },
                            ),
                          ],
                        if (canCheckIn) ...[
                          if (!collapsed) const SizedBox(width: ctaGap),
                          _CheckInButton(
                            width: iconOnly ? Sizes.cta : cta,
                            labelWidth: ctaLabelWidth,
                            iconOnly: iconOnly,
                            onTap: () => _go(Routes.checkIn),
                          ),
                          const SizedBox(width: ctaClear),
                        ],
                        const Spacer(),
                        _StatusSlot(user: user),
                        const SizedBox(width: split),
                        Container(width: 1, height: 28, color: c.line),
                        const SizedBox(width: split),
                        if (user != null) ...[
                          _UserButton(user: user, showName: showName),
                          const SizedBox(width: Space.x12),
                          _IconButton(
                            key: const ValueKey('shell.lock'),
                            icon: LucideIcons.lock,
                            tooltip: 'Lock screen',
                            background: c.surface,
                            onTap: () =>
                                ref.read(idleLockProvider.notifier).lockNow(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (!collapsed && activeIndex >= 0)
                  AnimatedPositioned(
                    key: const ValueKey('shell.indicator'),
                    duration: m.tabIndicator.duration,
                    curve: m.tabIndicator.curve,
                    left: tabX(activeIndex) + Space.x4,
                    width: tabWidths[activeIndex] - 2 * Space.x4,
                    bottom: 0,
                    height: Sizes.tabIndicator,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.marine,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(Sizes.tabIndicator),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The wordmark (Pirata One, marine, the name alone) and the role under it.
class _Brand extends StatelessWidget {
  const _Brand({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LodgingWordmark(
          size: WordmarkSize.topBar,
          onDark: false,
          showWord: false,
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            key: const ValueKey('shell.role'),
            maxLines: 1,
            softWrap: false,
            style: t.meta.copyWith(color: c.muted),
          ),
      ],
    );
  }
}

/// A 44 px top tab (Figma `v2/Top tab`): icon and label, a count badge, a
/// chevron when it opens a menu. Default: ink-soft text, muted icon.
/// Active: marine. Hover (mouse only): the app background, ink text.
/// Keyboard focus: the marine ring outside the pill.
class _TopTab extends StatefulWidget {
  const _TopTab({
    super.key,
    required this.anchorKey,
    required this.focusNode,
    required this.width,
    required this.label,
    required this.icon,
    required this.active,
    required this.badge,
    required this.badgeKey,
    required this.menu,
    required this.onTap,
  });

  final GlobalKey anchorKey;
  final FocusNode focusNode;
  final double width;
  final String label;
  final IconData icon;
  final bool active;
  final int badge;
  final Key badgeKey;
  final bool menu;
  final VoidCallback onTap;

  @override
  State<_TopTab> createState() => _TopTabState();
}

class _TopTabState extends State<_TopTab> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final fg = widget.active
        ? c.marine
        : _hover
        ? c.ink
        : c.inkSoft;
    final iconColor = widget.active ? c.marine : c.muted;
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.badge > 0
          ? '${widget.label}, ${widget.badge}'
          : widget.label,
      excludeSemantics: true,
      child: FocusRing(
        radius: Radii.tab,
        child: Material(
          key: widget.anchorKey,
          color: _hover && !widget.active ? c.surface : c.white,
          borderRadius: BorderRadius.circular(Radii.tab),
          child: InkWell(
            focusNode: widget.focusNode,
            borderRadius: BorderRadius.circular(Radii.tab),
            hoverColor: c.surface,
            focusColor: c.white.withValues(alpha: 0),
            onHover: (h) => setState(() => _hover = h),
            onTap: widget.onTap,
            child: SizedBox(
              width: widget.width,
              height: Sizes.target,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: tabPadding),
                child: Row(
                  children: [
                    Icon(widget.icon, size: tabIconSize, color: iconColor),
                    const SizedBox(width: tabGap),
                    // Never cut: the bar folds the tabs before a label
                    // would lose a letter.
                    Text(
                      widget.label,
                      maxLines: 1,
                      softWrap: false,
                      style: t.secondaryMedium.copyWith(color: fg),
                    ),
                    if (widget.badge > 0) ...[
                      const SizedBox(width: tabGap),
                      // Flexible: while a count changes, the old badge can
                      // be a pixel or two wider than the tab was sized for;
                      // the badge gives way, never the label.
                      Flexible(
                        child: CountBadge(widget.badge, key: widget.badgeKey),
                      ),
                    ],
                    if (widget.menu) ...[
                      const SizedBox(width: tabGap),
                      Icon(
                        LucideIcons.chevronDown,
                        size: tabChevron,
                        color: iconColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Check in button's two labels: at rest, and while hovered or
/// keyboard-focused.
const checkInLabel = 'Check in';
const checkInHoverLabel = 'Let’s go!';

/// The bar's primary action (story/ui-floating-nav): a 48 px red pill with
/// a white icon and label, opening the check-in. It reads as the one action
/// on the bar, never as another tab. Hovered or keyboard-focused, it lifts
/// (scale [LodgingMotion.ctaScale], a stronger shadow), its label becomes
/// "Let’s go!" and its icon nudges forward and back in a loop; leaving
/// settles it back. Its width fits the longer label, so nothing moves.
/// Reduced motion: the label still swaps; nothing moves or loops. Screen
/// readers always hear "Check in".
class _CheckInButton extends StatefulWidget {
  const _CheckInButton({
    required this.width,
    required this.labelWidth,
    required this.onTap,
    this.iconOnly = false,
  });

  final double width;

  /// The wider of the two labels.
  final double labelWidth;
  final VoidCallback onTap;

  /// On a folded bar too narrow for the label: a 48 px circle with the
  /// icon, "Check in" as its tooltip.
  final bool iconOnly;

  @override
  State<_CheckInButton> createState() => _CheckInButtonState();
}

class _CheckInButtonState extends State<_CheckInButton>
    with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(vsync: this);
  var _hover = false;
  var _focused = false;
  var _keyboard =
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  bool get _lifted => _hover || (_focused && _keyboard);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion may have been turned on or off.
    _syncLoop();
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    _loop.dispose();
    super.dispose();
  }

  void _onMode(FocusHighlightMode mode) {
    final keyboard = mode == FocusHighlightMode.traditional;
    if (keyboard == _keyboard) return;
    setState(() => _keyboard = keyboard);
    _syncLoop();
  }

  void _set({bool? hover, bool? focused}) {
    setState(() {
      _hover = hover ?? _hover;
      _focused = focused ?? _focused;
    });
    _syncLoop();
  }

  /// Loops the icon while lifted; otherwise lets it glide home (the nudge
  /// is 0 at both ends of a loop) and stops.
  void _syncLoop() {
    if (!mounted) return;
    final m = LodgingMotion.of(context);
    if (_lifted && !m.reduced) {
      if (!_loop.isAnimating) {
        _loop.duration = m.ctaLoop;
        _loop.repeat();
      }
      return;
    }
    if (m.reduced || _loop.value == 0) {
      _loop
        ..stop()
        ..value = 0;
      return;
    }
    final home = _loop.value < 0.5 ? 0.0 : 1.0;
    _loop
        .animateTo(home, duration: m.ctaHover.duration, curve: Curves.easeOut)
        .whenCompleteOrCancel(() {
          if (mounted && !_loop.isAnimating) _loop.value = 0;
        });
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final m = LodgingMotion.of(context);
    final lifted = _lifted;
    final shape = BorderRadius.circular(Radii.pill);
    final button = Semantics(
      button: true,
      label: checkInLabel,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: lifted ? m.ctaScale : 1,
        duration: m.ctaHover.duration,
        curve: m.ctaHover.curve,
        child: FocusRing(
          radius: Radii.pill,
          child: AnimatedContainer(
            key: const ValueKey('shell.checkIn'),
            duration: m.ctaHover.duration,
            curve: m.ctaHover.curve,
            width: widget.width,
            height: Sizes.cta,
            decoration: BoxDecoration(
              color: c.red,
              borderRadius: shape,
              boxShadow: lifted
                  ? LodgingShadows.ctaRaised(c)
                  : LodgingShadows.cta(c),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: shape,
                hoverColor: c.white.withValues(alpha: 0),
                focusColor: c.white.withValues(alpha: 0),
                highlightColor: c.white.withValues(alpha: 0.12),
                splashColor: c.white.withValues(alpha: 0.16),
                onHover: (h) => _set(hover: h),
                onFocusChange: (f) => _set(focused: f),
                onTap: widget.onTap,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _loop,
                        builder: (context, icon) => Transform.translate(
                          // Forward and back once per loop: 0 at both ends.
                          offset: Offset(
                            m.ctaNudge *
                                (1 - math.cos(2 * math.pi * _loop.value)) /
                                2,
                            0,
                          ),
                          child: icon,
                        ),
                        child: Icon(
                          LucideIcons.logIn,
                          key: const ValueKey('shell.checkIn.icon'),
                          size: Sizes.ctaIcon,
                          color: c.white,
                        ),
                      ),
                      if (!widget.iconOnly) ...[
                        const SizedBox(width: tabGap),
                        SizedBox(
                          width: widget.labelWidth,
                          child: AnimatedSwitcher(
                            duration: m.ctaHover.duration,
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.centerLeft,
                              children: [...previous, ?current],
                            ),
                            child: Text(
                              lifted ? checkInHoverLabel : checkInLabel,
                              key: ValueKey('shell.checkIn.$lifted'),
                              maxLines: 1,
                              softWrap: false,
                              style: t.bodyMedium.copyWith(color: c.white),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return widget.iconOnly
        ? Tooltip(message: checkInLabel, child: button)
        : button;
  }
}

/// A 44 px square button with a marine icon (Lock, the menu button).
class _IconButton extends StatelessWidget {
  const _IconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.onTap,
    this.focusNode,
  });

  final IconData icon;
  final String tooltip;
  final Color? background;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    return Tooltip(
      message: tooltip,
      child: FocusRing(
        radius: Radii.tab,
        child: Material(
          color: background ?? c.white,
          borderRadius: BorderRadius.circular(Radii.tab),
          child: InkWell(
            focusNode: focusNode,
            borderRadius: BorderRadius.circular(Radii.tab),
            hoverColor: c.lineSoft,
            focusColor: c.white.withValues(alpha: 0),
            onTap: onTap,
            child: SizedBox.square(
              dimension: Sizes.target,
              child: Icon(icon, size: Sizes.menuIcon, color: c.marine),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Status: backup and sync ───────────────────────────────────────────

/// The backup pill (only when the main backup failed or is overdue) and the
/// sync status (brief, "Shell states"): a green dot "Online", a muted dot
/// "Syncing · 3", a butter pill for offline and the other warnings, a
/// red-tint pill for a sync problem. The sync status opens the Cloud sync
/// panel.
class _StatusSlot extends ConsumerWidget {
  const _StatusSlot({required this.user});

  final UserAccount? user;

  static (String?, String, SyncBarTone) _texts(
    WidgetRef ref,
    UserAccount? user,
  ) {
    final backups = ref.watch(backupsProvider);
    final backup = backups.overdueAt(ref.watch(clockProvider).now())
        ? backupOverdueText(
            newest: backups.newest?.takenAt,
            failed: backups.lastFailure != null,
          )
        : null;
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    final status =
        ref.watch(syncStatusProvider).value ??
        const SyncStatus(phase: SyncPhase.notConfigured);
    final (sync, tone) = syncBarText(status, pending: pending);
    return (backup, sync, tone);
  }

  /// How wide the slot is, for the collapse rule.
  static double widthOf(
    WidgetRef ref,
    UserAccount? user,
    LodgingType t,
    TextScaler scaler,
  ) {
    final (backup, sync, tone) = _texts(ref, user);
    double pill(String text, {required bool padded}) =>
        Space.x8 +
        Space.x8 +
        _textWidth(text, t.meta, scaler) +
        (padded ? 2 * Space.x10 : 0);
    return (backup == null ? 0 : pill(backup, padded: true) + Space.x8) +
        pill(
          sync,
          padded: tone == SyncBarTone.warning || tone == SyncBarTone.problem,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final (backup, sync, tone) = _texts(ref, user);
    final canFix = user != null && can(user!, Permission.manageBackups);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (backup != null) ...[
          _StatusPill(
            key: const ValueKey('shell.backupPill'),
            text: backup,
            dot: c.butterText,
            background: c.butter,
            foreground: c.butterText,
            onTap: canFix ? () => context.go(Routes.adminPrices) : null,
          ),
          const SizedBox(width: Space.x8),
        ],
        _StatusPill(
          key: const ValueKey('shell.syncPill'),
          text: sync,
          dot: switch (tone) {
            SyncBarTone.online => c.green,
            SyncBarTone.muted => c.muted,
            SyncBarTone.warning => c.butterText,
            SyncBarTone.problem => c.redText,
          },
          background: switch (tone) {
            SyncBarTone.warning => c.butter,
            SyncBarTone.problem => c.redTint,
            _ => null,
          },
          foreground: switch (tone) {
            SyncBarTone.warning => c.butterText,
            SyncBarTone.problem => c.redText,
            _ => c.muted,
          },
          onTap: () => showSyncPanel(context),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    super.key,
    required this.text,
    required this.dot,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String text;
  final Color dot;

  /// A pill's fill; null for plain text ("Online", "Syncing · 3").
  final Color? background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: background == null ? 0 : Space.x10,
        vertical: Space.x4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: Space.x8,
            height: Space.x8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.x8),
          Text(text, style: t.meta.copyWith(color: foreground)),
        ],
      ),
    );
    final shape = BorderRadius.circular(Radii.pill);
    if (onTap == null) {
      return DecoratedBox(
        decoration: BoxDecoration(color: background, borderRadius: shape),
        child: content,
      );
    }
    return FocusRing(
      radius: Radii.pill,
      child: Material(
        color: background ?? c.white,
        borderRadius: shape,
        child: InkWell(
          borderRadius: shape,
          focusColor: c.white.withValues(alpha: 0),
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

// ── The user ───────────────────────────────────────────────────────────

/// The signed-in user's initials: marine-tint for a receptionist, butter
/// for the supervisor, marine with white letters for the owner.
class Avatar extends StatelessWidget {
  const Avatar(this.user, {super.key});

  final UserAccount user;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final (fill, ink) = switch (user.role) {
      Role.owner => (c.marine, c.white),
      Role.supervisor => (c.butter, c.butterText),
      Role.receptionist => (c.marineTint, c.marine),
    };
    return Container(
      width: Sizes.avatar,
      height: Sizes.avatar,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Text(
        initialsOf(user.fullName),
        style: t.meta.copyWith(color: ink),
      ),
    );
  }
}

/// Whose session and shift (brief, principle 6): "Shift since 07:02" while
/// this user has a shift of their own open, else the role.
String _userLine(WidgetRef ref, UserAccount user) {
  final shift = ref.watch(currentShiftProvider).value;
  if (shift != null && shift.userId == user.id) {
    return 'Shift since ${formatTime(shift.openedAt)}';
  }
  return switch (user.role) {
    Role.owner => 'Owner',
    Role.supervisor => 'Supervisor',
    Role.receptionist => 'Receptionist',
  };
}

/// The user menu's rows: Close shift (only with this user's own shift
/// open) and Change my password (the owner, as before).
List<ShellMenuRow> userMenuRows(WidgetRef ref, UserAccount user) {
  final shift = ref.watch(currentShiftProvider).value;
  final ownShift = shift != null && shift.userId == user.id;
  return [
    if (ownShift && can(user, Permission.closeShift))
      const ShellMenuRow(
        key: ValueKey('shell.closeShift'),
        icon: LucideIcons.logOut,
        label: 'Close shift',
        value: 'closeShift',
      ),
    if (can(user, Permission.ownerCloudPassword))
      const ShellMenuRow(
        key: ValueKey('shell.changeMyPassword'),
        icon: LucideIcons.keyRound,
        label: 'Change my password',
        value: 'changePassword',
      ),
  ];
}

/// Acts on a user menu row: Close shift goes to the close (a focused
/// flow), Change my password opens its dialog over the app (the menu or
/// drawer that offered it has closed by then).
void actOnUserRow(GoRouter router, String? value) {
  switch (value) {
    case 'closeShift':
      router.go(Routes.closeShift);
    case 'changePassword':
      final context = router.routerDelegate.navigatorKey.currentContext;
      if (context == null) return;
      showDialog<bool>(
        context: context,
        builder: (_) => const ChangeMyPasswordDialog(),
      );
  }
}

/// The version line at the foot of the user menu and the drawer: muted
/// Meta under a 1 px divider, read by screen readers, not focusable
/// (story/desk-db-guards).
class VersionFooter extends StatelessWidget {
  const VersionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, thickness: 1, color: c.line),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.x12,
            Space.x8,
            Space.x12,
            Space.x4,
          ),
          child: Text(
            versionLine(AppBuild.current, schemaVersion: latestSchemaVersion),
            key: const ValueKey('shell.version'),
            style: t.meta.copyWith(color: c.muted),
          ),
        ),
      ],
    );
  }
}

/// The avatar, name and shift (or role); opens the user menu. The name
/// hides while the tabs are collapsed.
class _UserButton extends ConsumerWidget {
  const _UserButton({required this.user, required this.showName});

  final UserAccount user;
  final bool showName;

  static double widthOf(
    WidgetRef ref,
    UserAccount? user,
    LodgingType t,
    TextScaler scaler,
  ) {
    if (user == null) return 0;
    return Sizes.avatar +
        Space.x12 +
        math.max(
          _textWidth(user.fullName, t.secondaryMedium, scaler),
          _textWidth(_userLine(ref, user), t.meta, scaler),
        ) +
        Space.x8;
  }

  /// What hiding the name saves: the gap after the avatar and the name or
  /// role line, whichever is wider.
  static double nameWidthOf(
    WidgetRef ref,
    UserAccount user,
    LodgingType t,
    TextScaler scaler,
  ) =>
      Space.x12 +
      math.max(
        _textWidth(user.fullName, t.secondaryMedium, scaler),
        _textWidth(_userLine(ref, user), t.meta, scaler),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final rows = userMenuRows(ref, user);
    final content = Padding(
      padding: const EdgeInsets.only(right: Space.x8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(user),
          if (showName) ...[
            const SizedBox(width: Space.x12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  key: const ValueKey('shell.userName'),
                  style: t.secondaryMedium,
                ),
                Text(
                  _userLine(ref, user),
                  key: const ValueKey('shell.userRole'),
                  style: t.meta.copyWith(color: c.muted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    return FocusRing(
      radius: Radii.tab,
      child: Material(
        color: c.white,
        borderRadius: BorderRadius.circular(Radii.tab),
        child: InkWell(
          key: const ValueKey('shell.user'),
          borderRadius: BorderRadius.circular(Radii.tab),
          hoverColor: c.surface,
          focusColor: c.white.withValues(alpha: 0),
          // Always opens: the version line is at its foot, even when it is
          // the only thing in it (story/desk-db-guards).
          onTap: () async {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final router = GoRouter.of(context);
            final value = await showShellMenu<String>(
              context,
              anchor: box.localToGlobal(Offset.zero) & box.size,
              label: 'Your menu',
              alignRight: true,
              rows: rows,
              footer: const VersionFooter(),
            );
            actOnUserRow(router, value);
          },
          child: SizedBox(height: Sizes.target, child: content),
        ),
      ),
    );
  }
}
