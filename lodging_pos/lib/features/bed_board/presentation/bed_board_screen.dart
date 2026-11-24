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
import '../../receipts/data/receipts_repository.dart';
import '../../receipts/presentation/receipts_providers.dart';
import '../../stays/presentation/bed_panel.dart';
import '../domain/bed_board.dart';
import 'bed_board_providers.dart';

/// FD-2 "Bed board", v2 (PR 5, Figma "Desk · Bed board — top nav", "— 1024
/// wide", "— 768 wide"): the date, the "Guest or receipt" search and New
/// check-in; the Now strip (Overstay, To clean); filter chips with a
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
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'board.search');
  BoardStatus? _status;
  String? _categoryId;

  String? _opened;

  @override
  void initState() {
    super.initState();
    _openFromAddress();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// The board's keys (design-system.md, "Bed board"), while it is the page
  /// in front (no panel or menu over it) and no field has the cursor (there,
  /// they are just characters): "/" goes to the search box, "N" starts a
  /// new check-in.
  bool _onKey(KeyEvent event) {
    final key = event.character?.toLowerCase();
    if (event is! KeyDownEvent || (key != '/' && key != 'n')) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    if (key == 'n') {
      final user = ref.read(sessionProvider);
      if (user == null || !can(user, Permission.checkIn)) return false;
      context.go(Routes.checkIn);
      return true;
    }
    _searchFocus.requestFocus();
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
    _search.dispose();
    _searchFocus.dispose();
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
      search: _search,
      searchFocus: _searchFocus,
      onSearchChanged: () => setState(() {}),
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
      BoardFilter(
        status: _status,
        categoryId: _categoryId,
        query: _search.text,
      ),
      now: now,
      graceMinutes: grace,
    );
    final toClean = [
      for (final r in [...list]..sort((a, b) => a.number.compareTo(b.number)))
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
        const SliverToBoxAdapter(child: SizedBox(height: Space.x20)),
        if (view.overstays.isNotEmpty || toClean.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _NowStrip(
              overstays: view.overstays,
              toClean: toClean,
              now: now,
              onExtend: canExtend ? openPanel : null,
              onCheckOut: canCheckOut ? openPanel : null,
              onClean: onClean,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Space.x20)),
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
        const SliverToBoxAdapter(child: SizedBox(height: Space.x20)),
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

/// The date and time, the "Guest or receipt" box (with up to five matching
/// receipts under it) and New check-in.
class _Header extends ConsumerWidget {
  const _Header({
    required this.now,
    required this.search,
    required this.searchFocus,
    required this.onSearchChanged,
    required this.onNewCheckIn,
  });

  final DateTime? now;
  final TextEditingController search;
  final FocusNode searchFocus;
  final VoidCallback onSearchChanged;
  final VoidCallback? onNewCheckIn;

  static const _searchWidth = 300.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final date = now == null ? '' : formatDayDateTime(now!);
    final term = receiptSearchTerm(search.text);
    final receipts = term == null
        ? const <ReceiptSummary>[]
        : (ref.watch(receiptListProvider(term)).value ?? const [])
              .take(5)
              .toList();

    final box = TextField(
      key: const ValueKey('board.search'),
      controller: search,
      focusNode: searchFocus,
      onChanged: (_) => onSearchChanged(),
      style: t.body,
      decoration: InputDecoration(
        hintText: 'Guest or receipt',
        prefixIcon: Icon(LucideIcons.search, size: 18, color: c.muted),
        suffixIcon: Padding(
          padding: const EdgeInsets.all(Space.x12),
          child: Container(
            width: 21,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.badge),
              border: Border.all(color: c.line),
            ),
            child: ExcludeSemantics(
              child: Text('/', style: t.meta.copyWith(color: c.muted)),
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(maxHeight: Sizes.target),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _searchWidth),
                child: box,
              ),
            ),
            if (onNewCheckIn != null) ...[
              const SizedBox(width: Space.x12),
              AppButton.primary(
                key: const ValueKey('board.newCheckIn'),
                label: 'New check-in',
                onPressed: onNewCheckIn,
              ),
            ],
          ],
        ),
        if (receipts.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(
                top: Space.x8,
                right: onNewCheckIn == null ? 0 : 133,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _searchWidth),
                child: _ReceiptResults(
                  receipts: receipts,
                  onOpen: (r) => context.go(
                    Routes.receiptFor(search.text.trim(), r.paymentId),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Up to five receipts matching the search, under the box.
class _ReceiptResults extends StatelessWidget {
  const _ReceiptResults({required this.receipts, required this.onOpen});

  final List<ReceiptSummary> receipts;
  final ValueChanged<ReceiptSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Container(
      key: const ValueKey('board.receipts'),
      padding: const EdgeInsets.all(Space.x6),
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in receipts)
            FocusRing(
              radius: Radii.tab,
              child: InkWell(
                key: ValueKey('board.receipt.${r.receiptNumber}'),
                borderRadius: BorderRadius.circular(Radii.tab),
                hoverColor: c.marineTint,
                onTap: () => onOpen(r),
                child: Container(
                  constraints: const BoxConstraints(minHeight: Sizes.target),
                  padding: const EdgeInsets.symmetric(horizontal: Space.x10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${r.receiptNumber} · ${shortGuestName(r.guestName)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.moneySmall.copyWith(color: c.ink),
                        ),
                      ),
                      const SizedBox(width: Space.x8),
                      Text(
                        formatKes(r.total),
                        style: t.moneySmall.copyWith(color: c.inkSoft),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Now strip: the Overstay card (the oldest, with Extend and Check out)
/// and the To clean card (a chip per bed). Side by side when there's room,
/// stacked below about 900 px; the overstay card stacks its guest above its
/// buttons when it's narrow.
class _NowStrip extends StatelessWidget {
  const _NowStrip({
    required this.overstays,
    required this.toClean,
    required this.now,
    required this.onExtend,
    required this.onCheckOut,
    required this.onClean,
  });

  final List<OverstayAlert> overstays;
  final List<(BoardRoom, BoardBed)> toClean;
  final DateTime now;
  final ValueChanged<String>? onExtend;
  final ValueChanged<String>? onCheckOut;
  final ValueChanged<String>? onClean;

  static const _sideBySide = 900.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final both = overstays.isNotEmpty && toClean.isNotEmpty;
        final sideBySide = both && constraints.maxWidth >= _sideBySide;
        final overstayWidth = sideBySide
            ? (constraints.maxWidth - Space.x12) / 2
            : constraints.maxWidth;
        final cards = [
          if (overstays.isNotEmpty)
            _OverstayCard(
              overstays,
              now: now,
              stacked: overstayWidth < _OverstayCard.stackBelow,
              onExtend: onExtend,
              onCheckOut: onCheckOut,
            ),
          if (toClean.isNotEmpty) _ToCleanCard(toClean, onClean: onClean),
        ];
        if (cards.length == 1) return cards.single;
        if (sideBySide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: Space.x12),
                Expanded(child: cards[1]),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cards[0],
            const SizedBox(height: Space.x12),
            cards[1],
          ],
        );
      },
    );
  }
}

/// A Now card's head: a 32 px tinted circle with its icon, the title and
/// the count.
class _NowHead extends StatelessWidget {
  const _NowHead({
    required this.icon,
    required this.circle,
    required this.iconColor,
    required this.title,
    required this.count,
    required this.textColor,
  });

  final IconData icon;
  final Color circle;
  final Color iconColor;
  final String title;
  final int count;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: circle, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: Space.x10),
        Text(title, style: t.secondaryMedium.copyWith(color: textColor)),
        const SizedBox(width: Space.x10),
        Text('$count', style: t.moneySmall.copyWith(color: textColor)),
      ],
    );
  }
}

class _OverstayCard extends StatelessWidget {
  const _OverstayCard(
    this.overstays, {
    required this.now,
    required this.stacked,
    required this.onExtend,
    required this.onCheckOut,
  });

  final List<OverstayAlert> overstays;
  final DateTime now;

  /// The guest above the buttons, when the card is narrow.
  final bool stacked;

  /// Each opens the oldest overstay's bed panel.
  final ValueChanged<String>? onExtend;
  final ValueChanged<String>? onCheckOut;

  /// Narrower than this, the card stacks the guest above its buttons.
  static const stackBelow = 560.0;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final first = overstays.first;
    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          overstayWho(first),
          key: const ValueKey('board.overstay.who'),
          style: t.body.copyWith(color: c.ink),
        ),
        Text(
          overstayPast(first, now: now),
          style: t.secondary.copyWith(color: c.redText),
        ),
      ],
    );
    final buttons = Wrap(
      spacing: Space.x8,
      runSpacing: Space.x8,
      children: [
        if (onExtend != null)
          AppButton.urgent(
            key: const ValueKey('board.overstay.extend'),
            label: 'Extend',
            onPressed: () => onExtend!(first.stayId),
          ),
        if (onCheckOut != null)
          AppButton.secondary(
            key: const ValueKey('board.overstay.checkOut'),
            label: 'Check out',
            onPressed: () => onCheckOut!(first.stayId),
          ),
      ],
    );
    return Container(
      key: const ValueKey('board.overstayBar'),
      padding: const EdgeInsets.all(Space.x16),
      decoration: BoxDecoration(
        color: c.redTint,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.redBorder),
      ),
      child: Builder(
        builder: (context) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _NowHead(
                icon: LucideIcons.triangleAlert,
                circle: c.red,
                iconColor: c.white,
                title: 'Overstay',
                count: overstays.length,
                textColor: c.redText,
              ),
              const SizedBox(height: Space.x12),
              if (stacked) ...[
                who,
                const SizedBox(height: Space.x12),
                buttons,
              ] else
                Row(
                  children: [
                    Expanded(child: who),
                    const SizedBox(width: Space.x8),
                    buttons,
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ToCleanCard extends StatelessWidget {
  const _ToCleanCard(this.beds, {required this.onClean});

  final List<(BoardRoom, BoardBed)> beds;
  final ValueChanged<String>? onClean;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    return Container(
      key: const ValueKey('board.toClean'),
      padding: const EdgeInsets.all(Space.x16),
      decoration: BoxDecoration(
        color: c.white,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _NowHead(
            icon: LucideIcons.bedDouble,
            circle: c.butter,
            iconColor: c.butterText,
            title: 'To clean',
            count: beds.length,
            textColor: c.ink,
          ),
          const SizedBox(height: Space.x12),
          Wrap(
            spacing: Space.x8,
            runSpacing: Space.x8,
            children: [
              for (final (room, bed) in beds)
                _CleanChip(
                  key: ValueKey(
                    'board.toClean.${room.number}${bed.label.code}',
                  ),
                  text: '${room.number} ${bed.label.code}',
                  onTap: onClean == null ? null : () => onClean!(bed.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CleanChip extends StatelessWidget {
  const _CleanChip({super.key, required this.text, required this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final chip = Container(
      constraints: const BoxConstraints(minHeight: Sizes.target),
      padding: const EdgeInsets.symmetric(horizontal: Space.x10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.butter,
        borderRadius: BorderRadius.circular(Radii.badge),
      ),
      child: Text(text, style: t.moneySmall.copyWith(color: c.butterText)),
    );
    return Semantics(
      button: onTap != null,
      label: 'Bed $text to clean',
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
