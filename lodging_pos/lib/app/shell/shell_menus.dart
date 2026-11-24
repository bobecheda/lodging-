part of 'desk_shell.dart';

// ── Menus ──────────────────────────────────────────────────────────────

/// A row of a shell menu (Setup ▾, More ▾, the user menu) and of the
/// drawer.
class ShellMenuRow {
  const ShellMenuRow({
    required this.key,
    required this.icon,
    required this.label,
    required this.value,
    this.active = false,
    this.badge = 0,
  });

  final Key key;
  final IconData icon;
  final String label;

  /// What choosing it returns.
  final String value;
  final bool active;
  final int badge;
}

/// Opens a menu under [anchor] (the Setup ▾ style: a white card, 1 px line
/// border, a soft shadow, 44 px rows, the hovered row marine-tint). It
/// drops 4 px as it fades in. Escape or a tap outside closes it; the
/// chosen row's value comes back.
Future<T?> showShellMenu<T>(
  BuildContext context, {
  required Rect anchor,
  required String label,
  required List<ShellMenuRow> rows,
  bool alignRight = false,
  Widget? footer,
}) {
  final c = LodgingColors.of(context);
  final m = LodgingMotion.of(context);
  return Navigator.of(context).push(
    ShellOverlayRoute<T>(
      label: 'Close the $label',
      inDuration: m.menuOpen.duration,
      outDuration: m.menuClose.duration,
      scrimDuration: m.menuOpen.duration,
      transition: (animation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: m.menuOpen.curve,
          reverseCurve: m.menuClose.curve.flipped,
        );
        return FadeTransition(
          opacity: curved,
          child: AnimatedBuilder(
            animation: curved,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, -m.menuDrop * (1 - curved.value)),
              child: child,
            ),
            child: child,
          ),
        );
      },
      builder: (context) => CustomSingleChildLayout(
        delegate: _MenuLayout(anchor, alignRight: alignRight),
        child: Container(
          key: const ValueKey('shell.menuCard'),
          width: Sizes.menuWidth,
          padding: const EdgeInsets.all(Space.x6),
          decoration: BoxDecoration(
            color: c.white,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: c.ink.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, r) in rows.indexed)
                  _MenuRow(
                    row: r,
                    height: Sizes.target,
                    autofocus: i == 0,
                    onTap: () => Navigator.of(context).pop(r.value),
                  ),
                ?footer,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout(this.anchor, {required this.alignRight});

  final Rect anchor;
  final bool alignRight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final left = alignRight ? anchor.right - child.width : anchor.left;
    return Offset(
      left.clamp(Space.x8, math.max(Space.x8, size.width - child.width - 8)),
      math.min(anchor.bottom + Space.x6, size.height - child.height),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout old) =>
      old.anchor != anchor || old.alignRight != alignRight;
}

/// One row of a menu or the drawer: icon, label, badge. The active row is
/// marine-tint with marine text; in the drawer it also has a 3 px marine
/// bar on its left edge.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.row,
    required this.height,
    required this.onTap,
    this.autofocus = false,
    this.drawer = false,
  });

  final ShellMenuRow row;
  final double height;
  final VoidCallback onTap;
  final bool autofocus;
  final bool drawer;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final fg = row.active ? c.marine : c.ink;
    final style = drawer ? t.bodyMedium : t.secondaryMedium;
    return Semantics(
      button: true,
      selected: row.active,
      child: FocusRing(
        radius: Radii.tab,
        child: Material(
          color: row.active ? c.marineTint : c.white.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(Radii.tab),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: row.key,
            autofocus: autofocus,
            hoverColor: c.marineTint,
            focusColor: c.white.withValues(alpha: 0),
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  if (drawer && row.active)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: Sizes.tabIndicator,
                      child: ColoredBox(color: c.marine),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x12),
                    child: Row(
                      children: [
                        Icon(
                          row.icon,
                          size: Sizes.menuIcon,
                          color: row.active ? c.marine : c.inkSoft,
                        ),
                        const SizedBox(width: Space.x12),
                        Expanded(
                          child: Text(
                            row.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(color: fg),
                          ),
                        ),
                        if (row.badge > 0)
                          CountBadge(
                            row.badge,
                            key: ValueKey('nav.badge.${row.value}'),
                          ),
                      ],
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
