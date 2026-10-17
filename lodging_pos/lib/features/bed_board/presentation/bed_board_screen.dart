import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/bed_status_tile.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../domain/bed_board.dart';
import 'bed_board_providers.dart';

/// FD-2 "Bed board": every active bed's status at a glance (artboard "Bed
/// board — front desk"). Read-only for now: FD-4 adds "New check-in" and
/// starting a check-in from a Ready bed; FD-7/8 add the overstay buttons and
/// the bed panel.
class BedBoardScreen extends ConsumerStatefulWidget {
  const BedBoardScreen({super.key});

  @override
  ConsumerState<BedBoardScreen> createState() => _BedBoardScreenState();
}

class _BedBoardScreenState extends ConsumerState<BedBoardScreen> {
  final _search = TextEditingController();
  BoardStatus? _status;
  String? _categoryId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final rooms = ref.watch(boardRoomsProvider);
    final grace = ref.watch(boardGraceMinutesProvider).value;
    final now = ref.watch(boardNowProvider).value;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('Bed board', style: t.pageTitle),
              ),
              const SizedBox(height: Space.x4),
              Text(
                now == null ? '' : formatDayDateTime(now),
                key: const ValueKey('board.now'),
                style: t.small,
              ),
            ],
          ),
        ),
        SizedBox(
          width: 340,
          child: TextField(
            key: const ValueKey('board.search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: t.body,
            decoration: InputDecoration(
              hintText: 'Find guest, phone or room',
              prefixIcon: Icon(Icons.search_rounded, color: c.muted),
            ),
          ),
        ),
      ],
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
    final categories = {
      for (final r in list)
        for (final b in r.beds) b.categoryId: b.categoryName,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: Space.x16),
        if (view.overstays.isNotEmpty) ...[
          _OverstayBar(view.overstays),
          const SizedBox(height: Space.x12),
        ],
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: Space.x8,
                runSpacing: Space.x8,
                children: [
                  _StatusChip(
                    key: const ValueKey('board.chip.all'),
                    label: 'All beds',
                    count: view.total,
                    selected: _status == null,
                    onTap: () => setState(() => _status = null),
                  ),
                  for (final s in BoardStatus.values)
                    _StatusChip(
                      key: ValueKey('board.chip.${s.name}'),
                      label: _chipLabel(s),
                      count: view.counts[s]!,
                      swatch: s,
                      selected: _status == s,
                      onTap: () => setState(() => _status = s),
                    ),
                ],
              ),
            ),
            _CategoryMenu(
              categories: categories,
              selected: _categoryId,
              onChanged: (id) => setState(() => _categoryId = id),
            ),
          ],
        ),
        const SizedBox(height: Space.x12),
        Expanded(
          child: list.isEmpty
              ? const Align(
                  alignment: Alignment.topCenter,
                  child: Note.info(
                    'No rooms yet. The owner adds them in Setup → Rooms & '
                    'beds.',
                  ),
                )
              : view.rooms.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    'No beds match.',
                    key: const ValueKey('board.noMatch'),
                    style: t.body,
                  ),
                )
              : _RoomGrid(rooms: view.rooms, now: now, graceMinutes: grace),
        ),
      ],
    );
  }

  static String _chipLabel(BoardStatus s) => switch (s) {
    BoardStatus.ready => 'Ready',
    BoardStatus.occupied => 'Occupied',
    BoardStatus.overstay => 'Overstay',
    BoardStatus.toClean => 'Needs cleaning',
  };
}

/// One line, fixed above the grid: the oldest overstay, and how many more.
/// The Extend and Check out buttons come with FD-7/FD-8.
class _OverstayBar extends StatelessWidget {
  const _OverstayBar(this.overstays);

  final List<OverstayAlert> overstays;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final first = overstays.first;
    final more = overstays.length - 1;
    return Container(
      key: const ValueKey('board.overstayBar'),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x16,
        vertical: Space.x12,
      ),
      decoration: BoxDecoration(
        color: c.redTint,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.redBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: c.redText, size: 20),
          const SizedBox(width: Space.x12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        'Overstay · Room ${first.roomNumber}, Bed '
                        '${first.label.code} · ${first.guestName}',
                    style: t.bodyStrong.copyWith(color: c.redText),
                  ),
                  TextSpan(
                    text:
                        '  Paid to ${formatWeekdayTime(first.paidUntil)}; '
                        'grace ended ${formatTime(first.graceEnded)}.'
                        '${more > 0 ? '  And $more more.' : ''}',
                    style: t.body.copyWith(color: c.redText),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.swatch,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final BoardStatus? swatch;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final fg = selected ? c.white : c.ink;
    final (Color? fill, Color border) = switch (swatch) {
      null => (null, c.marine),
      BoardStatus.ready => (c.white, c.marine),
      BoardStatus.occupied => (c.marine, c.marine),
      BoardStatus.overstay => (c.red, c.redDark),
      BoardStatus.toClean => (c.butter, c.butterBorder),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      excludeSemantics: true,
      child: Material(
        color: selected ? c.marine : c.white,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? c.marine : c.line),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: Sizes.targetCompact,
            padding: const EdgeInsets.symmetric(horizontal: Space.x14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (fill != null) ...[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(Radii.badge),
                      border: Border.all(color: border, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: Space.x8),
                ],
                Text(label, style: t.bodyStrong.copyWith(color: fg)),
                const SizedBox(width: Space.x8),
                Text('$count', style: t.monoStrong.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  /// id → name, from the beds on the board.
  final Map<String, String> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final names = categories.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        key: const ValueKey('board.category'),
        value: categories.containsKey(selected) ? selected : null,
        style: t.bodyStrong.copyWith(color: c.marine),
        icon: Icon(Icons.expand_more_rounded, color: c.marine),
        borderRadius: BorderRadius.circular(Radii.control),
        dropdownColor: c.white,
        items: [
          const DropdownMenuItem(value: null, child: Text('All categories')),
          for (final e in names)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Room cards in columns of at least 250px; cards in a row share a height.
class _RoomGrid extends StatelessWidget {
  const _RoomGrid({
    required this.rooms,
    required this.now,
    required this.graceMinutes,
  });

  final List<BoardRoom> rooms;
  final DateTime now;
  final int graceMinutes;

  static const _minCard = 250.0;
  static const _gap = Space.x12;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = ((constraints.maxWidth + _gap) / (_minCard + _gap))
          .floor()
          .clamp(1, 12);
      final rowCount = (rooms.length / columns).ceil();
      return ListView.separated(
        key: const ValueKey('board.grid'),
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

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.now,
    required this.graceMinutes,
  });

  final BoardRoom room;
  final DateTime now;
  final int graceMinutes;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final beds = room.beds.length;
    return Card(
      key: ValueKey('board.room.${room.number}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.x14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Room ${room.number}', style: t.bodyStrong),
                ),
                Text(
                  beds == 1 ? '1 bed' : '$beds beds',
                  style: t.small.copyWith(color: c.muted),
                ),
              ],
            ),
            for (final bed in room.beds) ...[
              const SizedBox(height: Space.x8),
              _tile(bed),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(BoardBed bed) {
    final stay = bed.stay;
    final key = ValueKey('board.bed.${room.number}${bed.label.code}');
    return switch (statusOf(bed, now: now, graceMinutes: graceMinutes)) {
      BoardStatus.ready => BedStatusTile(
        key: key,
        label: bed.label.code,
        title: bed.categoryName,
        subtitle: '${formatKes(bed.pricePerNight)} / night',
        status: BedTileStatus.ready,
      ),
      BoardStatus.occupied => BedStatusTile(
        key: key,
        label: bed.label.code,
        title: stay!.guestName,
        // Time first: if the line is cut, the category goes, not the time.
        subtitle:
            'until ${formatWeekdayTime(stay.paidUntil)} · ${bed.categoryName}',
        status: BedTileStatus.occupied,
      ),
      BoardStatus.overstay => BedStatusTile(
        key: key,
        label: bed.label.code,
        title: stay!.guestName,
        subtitle:
            'paid to ${formatWeekdayTime(stay.paidUntil)} · '
            '${bed.categoryName}',
        status: BedTileStatus.overstay,
      ),
      BoardStatus.toClean => BedStatusTile(
        key: key,
        label: bed.label.code,
        title: bed.categoryName,
        subtitle: 'Needs cleaning',
        status: BedTileStatus.toClean,
      ),
    };
  }
}
