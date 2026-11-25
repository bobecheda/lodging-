import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/gate.dart';
import '../../../app/shell/desk_shell.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/bed_status_tile.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/focus_ring.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../housekeeping/presentation/cleaning_panel.dart';
import '../../setup/domain/rooms.dart';
import '../../stays/presentation/bed_panel.dart';
import '../domain/bed_board.dart';
import 'bed_board_providers.dart';

/// FD-2 "Bed board", v2 (PR 5, Figma "Desk · Bed board — top nav", "— 1024
/// wide", "— 768 wide"; fixed 25 Nov): the date and New check-in; the Now
/// strip, a summary (Overstay, To clean); filter chips with a
/// category menu; room cards with their category stripe. A Ready tile
/// starts a check-in; Occupied and Overstay tiles open the bed panel (FD-7,
/// FD-8); To clean tiles the cleaning panel (FD-9).
class BedBoardScreen extends ConsumerStatefulWidget {
  const BedBoardScreen({super.key, this.openStayId});

  /// `/home?stay=<id>`: open that stay's bed panel, e.g. coming back after
  /// opening a shift from it.
  final String? openStayId;

  @override
  ConsumerState<BedBoardScreen> createState() => _BedBoardScreenState();
}

class _BedBoardScreenState extends ConsumerState<BedBoardScreen> {
  BoardStatus? _status;
  String? _categoryId;

  String? _opened;

  @override
  void initState() {
    super.initState();
    _openFromAddress();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// "N" starts a new check-in (design-system.md, "Bed board"), while the
  /// board is the page in front (no panel or menu over it) and no field has
  /// the cursor (there, it's just a letter).
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.character?.toLowerCase() != 'n') {
      return false;
    }
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    final user = ref.read(sessionProvider);
    if (user == null || !can(user, Permission.checkIn)) return false;
    context.go(Routes.checkIn);
    return true;
  }

  @override
  void didUpdateWidget(BedBoardScreen old) {
    super.didUpdateWidget(old);
    _openFromAddress();
  }

  void _openFromAddress() {
    final id = widget.openStayId;
    if (id == null || id == _opened) return;
    _opened = id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showBedPanel(context, id);
      _opened = null;
      if (mounted) context.go(Routes.home);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final rooms = ref.watch(boardRoomsProvider);
    final grace = ref.watch(boardGraceMinutesProvider).value;
    final now = ref.watch(boardNowProvider).value;
    final user = ref.watch(sessionProvider);
    final canCheckIn = user != null && can(user, Permission.checkIn);
    final canCheckOut = user != null && can(user, Permission.checkOut);
    final canExtend = user != null && can(user, Permission.extendStay);
    final canClean =
        user != null &&
        (can(user, Permission.assignHousekeeping) ||
            can(user, Permission.markClean));
    void openPanel(String stayId) => showBedPanel(context, stayId);
    final onClean = canClean
        ? (String bedId) => showCleaningPanel(context, bedId)
        : null;

    final header = _Header(
      now: now,
      onNewCheckIn: canCheckIn ? () => context.go(Routes.checkIn) : null,
    );

    final list = rooms.value;
    if (rooms case AsyncError(:final error)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: Space.x16),
          Note.error('$error', title: 'The bed board could not be loaded.'),
        ],
      );
    }
    if (list == null || grace == null || now == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    final view = boardView(
      list,
      BoardFilter(status: _status, categoryId: _categoryId),
      now: now,
      graceMinutes: grace,
    );
    final toClean = [
      for (final r in [
        ...list,
      ]..sort((a, b) => compareRoomNumbers(a.number, b.number)))
        for (final b in r.beds)
          if (statusOf(b, now: now, graceMinutes: grace) == BoardStatus.toClean)
            (r, b),
    ];
    final categories = <String, (String, String)>{
      for (final r in list)
        for (final b in r.beds)
          b.categoryId: (b.categoryName, b.categoryColour),
    };

    final grid = list.isEmpty
        ? const SliverToBoxAdapter(
            child: Note.info(
              'No rooms yet. The supervisor adds them in Setup → Rooms & beds.',
            ),
          )
        : view.rooms.isEmpty
        ? SliverToBoxAdapter(
            child: Text(
              'No beds match.',
              key: const ValueKey('board.noMatch'),
              style: t.body,
            ),
          )
        : _RoomGrid(
            rooms: view.rooms,
            now: now,
            graceMinutes: grace,
            onOpen: canCheckOut ? openPanel : null,
            onClean: onClean,
            onLet: canCheckIn
                ? (bedId) => context.go(Routes.checkInFor(bedId))
                : null,
          );

    return CustomScrollView(
      key: const ValueKey('board.grid'),
      slivers: [
        SliverToBoxAdapter(child: header),
        const SliverToBoxAdapter(child: SizedBox(height: Space.x16)),
        if (view.overstays.isNotEmpty || toClean.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _NowStrip(
              overstays: view.overstays,
              toClean: toClean,
              now: now,
              onOpen: canCheckOut || canExtend ? openPanel : null,
              onClean: onClean,
              onShowAll: (s) => setState(() => _status = s),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Space.x16)),
        ],
        SliverToBoxAdapter(
          child: Wrap(
            spacing: Space.x8,
            runSpacing: Space.x8,
            children: [
              _FilterChip(
                key: const ValueKey('board.chip.all'),
                label: 'All',
                count: view.total,
                selected: _status == null,
                onTap: () => setState(() => _status = null),
              ),
              for (final s in BoardStatus.values)
                _FilterChip(
                  key: ValueKey('board.chip.${s.name}'),
                  label: _chipLabel(s),
                  count: view.counts[s]!,
                  selected: _status == s,
                  onTap: () => setState(() => _status = s),
                ),
              _CategoryChip(
                categories: categories,
                selected: _categoryId,
                onChanged: (id) => setState(() => _categoryId = id),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Space.x16)),
        grid,
        const SliverToBoxAdapter(child: SizedBox(height: Space.x24)),
      ],
    );
  }

  static String _chipLabel(BoardStatus s) => switch (s) {
    BoardStatus.ready => 'Ready',
    BoardStatus.occupied => 'Occupied',
    BoardStatus.overstay => 'Overstay',
    BoardStatus.toClean => 'To clean',
  };
}

/// The date and time, and New check-in. (The "Guest or receipt" search was
/// dropped on 25 Nov: guests are found on Guests, receipts on Receipts.)
class _Header extends StatelessWidget {
  const _Header({required this.now, required this.onNewCheckIn});

  final DateTime? now;
  final VoidCallback? onNewCheckIn;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final date = now == null ? '' : formatDayDateTime(now!);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            label: 'Bed board, $date',
            excludeSemantics: true,
            child: Text(
              date,
              key: const ValueKey('board.now'),
              style: t.secondary.copyWith(color: c.muted),
            ),
          ),
        ),
        if (onNewCheckIn != null)
          AppButton.primary(
            key: const ValueKey('board.newCheckIn'),
            label: 'New check-in',
            onPressed: onNewCheckIn,
          ),
      ],
    );
  }
}

/// The Now strip, a summary and never a list (brief, "Bed board — fixes
/// after the first build"): an Overstay card (up to 3 rows, with "Show all"
/// in its title line when there are more) and a To clean card (chips in up to 2 lines, then "+ N
/// more"), each only when it has something. Side by side, the same height,
/// in a window 1024 wide or more; stacked below that.
class _NowStrip extends StatelessWidget {
  const _NowStrip({
    required this.overstays,
    required this.toClean,
    required this.now,
    required this.onOpen,
    required this.onClean,
    required this.onShowAll,
  });

  final List<OverstayAlert> overstays;
  final List<(BoardRoom, BoardBed)> toClean;
  final DateTime now;

  /// Opens an overstay's bed panel (Extend and Check out live there).
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onClean;

  /// "Show all": the board's filter chip for that status.
  final ValueChanged<BoardStatus> onShowAll;

  static const _sideBySideWindow = 1024.0;

  @override
  Widget build(BuildContext context) {
    final sideBySide =
        overstays.isNotEmpty &&
        toClean.isNotEmpty &&
        MediaQuery.sizeOf(context).width >= _sideBySideWindow;
    return LayoutBuilder(
      builder: (context, box) {
        final cardWidth = sideBySide
            ? (box.maxWidth - Space.x12) / 2
            : box.maxWidth;
        final overstay = overstays.isEmpty
            ? null
            : _OverstayCard(
                overstays,
                now: now,
                onOpen: onOpen,
                onShowAll: () => onShowAll(BoardStatus.overstay),
              );
        final clean = toClean.isEmpty
            ? null
            : _ToCleanCard(
                toClean,
                chipsWidth: cardWidth - 2 * _NowCard.padX - 2,
                onClean: onClean,
                onShowAll: () => onShowAll(BoardStatus.toClean),
              );
        if (sideBySide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: overstay!),
                const SizedBox(width: Space.x12),
                Expanded(child: clean!),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?overstay,
            if (overstay != null && clean != null)
              const SizedBox(height: Space.x12),
            ?clean,
          ],
        );
      },
    );
  }
}

/// A Now card: its colours, a head (a 28 px tinted circle with the icon,
/// the title, the count and an optional [action] after a "·") and its body.
class _NowCard extends StatelessWidget {
  const _NowCard({
    super.key,
    this.action,
    required this.background,
    required this.border,
    required this.icon,
    required this.circle,
    required this.iconColor,
    required this.title,
    required this.count,
    required this.textColor,
    required this.body,
  });

  final Color background;
  final Color border;
  final IconData icon;
  final Color circle;
  final Color iconColor;
  final String title;
  final int count;
  final Color textColor;
  final Widget body;

  /// After the count, e.g. "Show all".
  final Widget? action;

  static const padX = Space.x16;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(padX, Space.x12, padX, Space.x12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: circle,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: Space.x10),
              Text(title, style: t.secondaryMedium.copyWith(color: textColor)),
              const SizedBox(width: Space.x8),
              Text('$count', style: t.moneySmall.copyWith(color: textColor)),
              if (action != null) ...[
                const SizedBox(width: Space.x6),
                Text('·', style: t.secondaryMedium.copyWith(color: textColor)),
                action!,
              ],
            ],
          ),
          const SizedBox(height: Space.x6),
          body,
        ],
      ),
    );
  }
}

class _OverstayCard extends StatelessWidget {
  const _OverstayCard(
    this.overstays, {
    required this.now,
    required this.onOpen,
    required this.onShowAll,
  });

  /// Oldest first.
  final List<OverstayAlert> overstays;
  final DateTime now;
  final ValueChanged<String>? onOpen;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final rows = nowRows(overstays.length);
    return _NowCard(
      key: const ValueKey('board.overstayBar'),
      background: c.redTint,
      border: c.redBorder,
      icon: LucideIcons.triangleAlert,
      circle: c.red,
      iconColor: c.white,
      title: 'Overstay',
      count: overstays.length,
      textColor: c.redText,
      action: rows.more == 0
          ? null
          : _NowRow(
              key: const ValueKey('board.overstay.more'),
              semanticLabel: '${overstays.length} overstays. Show all',
              onTap: onShowAll,
              child: Text(
                'Show all',
                style: t.secondaryMedium.copyWith(color: c.redText),
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in overstays.take(rows.shown))
            _NowRow(
              key: ValueKey('board.overstay.${a.roomNumber}${a.label.code}'),
              semanticLabel:
                  '${overstayWho(a)}, '
                  '${overstayLength(now.difference(a.paidUntil))} past '
                  'checkout',
              onTap: onOpen == null ? null : () => onOpen!(a.stayId),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      overstayWho(a),
                      style: t.bodyMedium.copyWith(color: c.ink),
                    ),
                  ),
                  const SizedBox(width: Space.x8),
                  Text(
                    overstayLength(now.difference(a.paidUntil)),
                    style: t.secondary.copyWith(color: c.redText),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A 44 px tappable row of a Now card.
class _NowRow extends StatelessWidget {
  const _NowRow({
    super.key,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: Sizes.target),
      padding: const EdgeInsets.symmetric(horizontal: Space.x8),
      alignment: AlignmentDirectional.centerStart,
      child: child,
    );
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: onTap == null
          ? row
          : FocusRing(
              radius: Radii.tab,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.tab),
                  onTap: onTap,
                  child: row,
                ),
              ),
            ),
    );
  }
}

class _ToCleanCard extends StatelessWidget {
  const _ToCleanCard(
    this.beds, {
    required this.chipsWidth,
    required this.onClean,
    required this.onShowAll,
  });

  final List<(BoardRoom, BoardBed)> beds;

  /// The width the chips wrap in.
  final double chipsWidth;
  final ValueChanged<String>? onClean;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final style = t.moneySmall;
    String name(BoardRoom r, BoardBed b) => '${r.number} ${b.label.code}';
    final shown = chipsThatFit(
      widths: [
        for (final (r, b) in beds)
          _CleanChip.widthOf(name(r, b), style, scaler),
      ],
      maxWidth: chipsWidth,
      gap: Space.x8,
      lines: 2,
      moreWidth: (n) => _CleanChip.widthOf('+ $n more', style, scaler),
    );
    final more = beds.length - shown;
    return _NowCard(
      key: const ValueKey('board.toClean'),
      background: c.white,
      border: c.line,
      icon: LucideIcons.bedDouble,
      circle: c.butter,
      iconColor: c.butterText,
      title: 'To clean',
      count: beds.length,
      textColor: c.ink,
      body: Padding(
        padding: const EdgeInsets.only(top: Space.x4),
        child: Wrap(
          spacing: Space.x8,
          runSpacing: Space.x8,
          children: [
            for (final (r, b) in beds.take(shown))
              _CleanChip(
                key: ValueKey('board.toClean.${r.number}${b.label.code}'),
                text: name(r, b),
                semanticLabel: 'Bed ${name(r, b)} to clean',
                onTap: onClean == null ? null : () => onClean!(b.id),
              ),
            if (more > 0)
              _CleanChip(
                key: const ValueKey('board.toClean.more'),
                text: '+ $more more',
                semanticLabel: '$more more beds to clean. Show all',
                onTap: onShowAll,
              ),
          ],
        ),
      ),
    );
  }
}

/// A 36 px butter chip that hugs its text.
class _CleanChip extends StatelessWidget {
  const _CleanChip({
    super.key,
    required this.text,
    required this.semanticLabel,
    required this.onTap,
  });

  final String text;
  final String semanticLabel;
  final VoidCallback? onTap;

  static const _padX = Space.x10;

  /// The chip's width for [text]: its padding and the text, rounded up.
  static double widthOf(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble() + 2 * _padX;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final chip = Container(
      height: Sizes.targetCompact,
      padding: const EdgeInsets.symmetric(horizontal: _padX),
      decoration: BoxDecoration(
        color: c.butter,
        borderRadius: BorderRadius.circular(Radii.badge),
      ),
      // widthFactor 1: the chip hugs its text instead of filling the row
      // (an alignment here made each chip a full-width bar).
      child: Center(
        widthFactor: 1,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: t.moneySmall.copyWith(color: c.butterText),
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: onTap == null
          ? chip
          : FocusRing(
              radius: Radii.badge,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.badge),
                  onTap: onTap,
                  child: chip,
                ),
              ),
            ),
    );
  }
}

/// v2/Filter chip: a 36 px pill with its label and count; the selected one
/// marine-tint with a marine border.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      child: FocusRing(
        radius: Radii.pill,
        child: Material(
          color: selected ? c.marineTint : c.white,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? c.marine : c.line,
              width: selected ? Sizes.borderStrong : Sizes.borderThin,
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              height: Sizes.targetCompact,
              padding: const EdgeInsets.symmetric(horizontal: Space.x12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: t.secondary.copyWith(
                      color: selected ? c.marine : c.ink,
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: Space.x6),
                    Text(
                      '$count',
                      style: t.moneySmall.copyWith(
                        color: selected ? c.marine : c.inkSoft,
                      ),
                    ),
                  ],
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Category ▾": the last chip; its menu (the Setup ▾ style) narrows the
/// board to one category, each row with its colour.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  /// id → (name, colour key), from the beds on the board.
  final Map<String, (String, String)> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  static const _all = '';

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final current = categories[selected];
    final names = categories.entries.toList()
      ..sort((a, b) => a.value.$1.compareTo(b.value.$1));
    return Builder(
      builder: (context) => _FilterChip(
        key: const ValueKey('board.category'),
        label: current?.$1 ?? 'Category',
        count: null,
        selected: current != null,
        trailing: Padding(
          padding: const EdgeInsets.only(left: Space.x4),
          child: Icon(
            LucideIcons.chevronDown,
            size: 16,
            color: current == null ? c.inkSoft : c.marine,
          ),
        ),
        onTap: () async {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          Widget swatch(String key) => Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: c.category(key).stripe,
              borderRadius: BorderRadius.circular(4),
            ),
          );
          final chosen = await showShellMenu<String>(
            context,
            anchor: box.localToGlobal(Offset.zero) & box.size,
            label: 'category menu',
            rows: [
              ShellMenuRow(
                key: const ValueKey('board.category.all'),
                icon: LucideIcons.layoutGrid,
                label: 'All categories',
                value: _all,
                active: current == null,
              ),
              for (final e in names)
                ShellMenuRow(
                  key: ValueKey('board.category.${e.key}'),
                  leading: swatch(e.value.$2),
                  label: e.value.$1,
                  value: e.key,
                  active: e.key == selected,
                ),
            ],
          );
          if (chosen == null) return;
          onChanged(chosen == _all ? null : chosen);
        },
      ),
    );
  }
}

/// Room cards in columns of at least 190px (6 at 1366, 4 at 1024, 3 at
/// 768, 2 narrower); cards in a row share a height.
class _RoomGrid extends StatelessWidget {
  const _RoomGrid({
    required this.rooms,
    required this.now,
    required this.graceMinutes,
    required this.onLet,
    required this.onOpen,
    required this.onClean,
  });

  final List<BoardRoom> rooms;
  final DateTime now;
  final int graceMinutes;

  /// Starts a check-in on a Ready bed; null without [Permission.checkIn].
  final ValueChanged<String>? onLet;

  /// Opens an Occupied or Overstay bed's panel with its stay id (FD-8).
  final ValueChanged<String>? onOpen;

  /// Opens a To clean bed's cleaning panel with its bed id (FD-9).
  final ValueChanged<String>? onClean;

  static const _minCard = 190.0;
  static const _gap = Space.x12;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final columns = ((constraints.crossAxisExtent + _gap) / (_minCard + _gap))
          .floor()
          .clamp(1, 12);
      final rowCount = (rooms.length / columns).ceil();
      return SliverList.separated(
        itemCount: rowCount,
        separatorBuilder: (_, _) => const SizedBox(height: _gap),
        itemBuilder: (context, row) {
          final start = row * columns;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < columns; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  Expanded(
                    child: start + i < rooms.length
                        ? _RoomCard(
                            room: rooms[start + i],
                            now: now,
                            graceMinutes: graceMinutes,
                            onLet: onLet,
                            onOpen: onOpen,
                            onClean: onClean,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}

/// A room: its category stripe (two halves when its beds differ), the room
/// number and category name, then a tile per bed.
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.now,
    required this.graceMinutes,
    required this.onLet,
    required this.onOpen,
    required this.onClean,
  });

  final ValueChanged<String>? onLet;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onClean;

  final BoardRoom room;
  final DateTime now;
  final int graceMinutes;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final categories = roomCategories(room);
    return Container(
      key: ValueKey('board.room.${room.number}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 4,
            child: Row(
              children: [
                for (final (_, colour) in categories)
                  Expanded(child: ColoredBox(color: c.category(colour).stripe)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x12,
              Space.x10,
              Space.x12,
              Space.x12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        room.number,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        semanticsLabel: 'Room ${room.number}',
                        style: t.secondaryMedium.copyWith(color: c.ink),
                      ),
                    ),
                    for (final (i, (name, colour)) in categories.indexed) ...[
                      if (i > 0)
                        Text(' · ', style: t.meta.copyWith(color: c.muted)),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.meta.copyWith(
                            color: c.category(colour).text,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                for (final bed in room.beds) ...[
                  const SizedBox(height: Space.x6),
                  _tile(bed),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BoardBed bed) {
    final stay = bed.stay;
    final key = ValueKey('board.bed.${room.number}${bed.label.code}');
    final status = statusOf(bed, now: now, graceMinutes: graceMinutes);
    final line = tileLine(bed, status, now: now);
    return switch (status) {
      BoardStatus.ready => BedStatusTile(
        key: key,
        label: bed.label.code,
        text: line,
        semanticLabel:
            '${bed.categoryName}, ${formatKes(bed.pricePerNight)} a night',
        status: BedTileStatus.ready,
        // Only Ready beds can be let (BR-5).
        onTap: onLet == null ? null : () => onLet!(bed.id),
      ),
      BoardStatus.occupied => BedStatusTile(
        key: key,
        label: bed.label.code,
        text: line,
        semanticLabel:
            '${stay!.guestName}, until ${formatWeekdayTime(stay.paidUntil)}',
        status: BedTileStatus.occupied,
        onTap: onOpen == null ? null : () => onOpen!(stay.stayId),
      ),
      BoardStatus.overstay => BedStatusTile(
        key: key,
        label: bed.label.code,
        text: line,
        semanticLabel:
            '${stay!.guestName}, paid to ${formatWeekdayTime(stay.paidUntil)}',
        status: BedTileStatus.overstay,
        onTap: onOpen == null ? null : () => onOpen!(stay.stayId),
      ),
      BoardStatus.toClean => BedStatusTile(
        key: key,
        label: bed.label.code,
        text: line,
        status: BedTileStatus.toClean,
        onTap: onClean == null ? null : () => onClean!(bed.id),
      ),
    };
  }
}
