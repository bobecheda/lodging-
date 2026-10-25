import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/dashed_border.dart';
import '../../../app/widgets/notes.dart';
import '../../bed_board/domain/bed_board.dart';
import '../data/owner_cloud.dart';
import 'owner_providers.dart';

/// The owner's Beds (Figma "05 Beds"), read-only: each bed's status worked
/// out like the desk's board (`statusOf`: active stays, the grace setting
/// and the server's time; never stored). Status only: no guest is named
/// anywhere, not even in the overstay alert.
class OwnerBedsScreen extends ConsumerStatefulWidget {
  const OwnerBedsScreen({super.key});

  @override
  ConsumerState<OwnerBedsScreen> createState() => _OwnerBedsState();
}

class _OwnerBedsState extends ConsumerState<OwnerBedsScreen> {
  BoardStatus? _only;

  static const _order = [
    BoardStatus.occupied,
    BoardStatus.overstay,
    BoardStatus.toClean,
    BoardStatus.ready,
  ];

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final now = ref.watch(ownerClockProvider).now();
    final data = ref.watch(ownerTodayDataProvider);
    final today = data.value?.today;
    if (today == null) {
      return data.hasError
          ? Padding(
              padding: const EdgeInsets.all(Space.x16),
              child: Note.error(
                data.error is OwnerCloudOffline
                    ? 'No internet connection. Beds show once the phone is '
                          'online.'
                    : '${data.error}',
                title: 'Beds could not be loaded.',
              ),
            )
          : const Center(child: CircularProgressIndicator());
    }
    final all = boardView(
      today.rooms,
      const BoardFilter(),
      now: now,
      graceMinutes: today.graceMinutes,
    );
    final shown = _only == null
        ? all
        : boardView(
            today.rooms,
            BoardFilter(status: _only),
            now: now,
            graceMinutes: today.graceMinutes,
          );
    return RefreshIndicator(
      onRefresh: () => ref.read(ownerTodayDataProvider.notifier).refresh(),
      child: ListView(
        key: const ValueKey('owner.beds'),
        padding: const EdgeInsets.all(Space.x16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Semantics(
            header: true,
            child: Text('Beds right now', style: t.pageTitle),
          ),
          const SizedBox(height: Space.x12),
          if (all.overstays.isNotEmpty) ...[
            Container(
              key: const ValueKey('owner.beds.overstays'),
              padding: const EdgeInsets.all(Space.x14),
              decoration: BoxDecoration(
                color: c.redTint,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: c.redBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overstayCount(all.overstays.length),
                    style: t.bodyStrong.copyWith(color: c.redText),
                  ),
                  for (final (i, a) in all.overstays.indexed)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.x4),
                      child: Text(
                        overstayLine(a, now: now),
                        key: ValueKey('owner.beds.overstay.$i'),
                        style: t.body.copyWith(color: c.redText),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.x12),
          ],
          Row(
            children: [
              for (final (i, s) in _order.indexed) ...[
                if (i > 0) const SizedBox(width: Space.x8),
                Expanded(
                  child: _CountTile(
                    s,
                    all.counts[s] ?? 0,
                    selected: _only == s,
                    onTap: () => setState(() => _only = _only == s ? null : s),
                  ),
                ),
              ],
            ],
          ),
          if (_only case final only?) ...[
            const SizedBox(height: Space.x8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${only.label} only.',
                    key: const ValueKey('owner.beds.filter'),
                    style: t.small.copyWith(color: c.inkSoft),
                  ),
                ),
                TextButton(
                  key: const ValueKey('owner.beds.showAll'),
                  onPressed: () => setState(() => _only = null),
                  child: const Text('Show all'),
                ),
              ],
            ),
          ],
          const SizedBox(height: Space.x12),
          if (shown.rooms.isEmpty)
            Text(
              _only == null ? 'No beds yet.' : 'No beds are ${_only!.label}.',
              style: t.body.copyWith(color: c.inkSoft),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 320 ? 2 : 1;
              final width =
                  (constraints.maxWidth - Space.x12 * (columns - 1)) / columns;
              return Wrap(
                spacing: Space.x12,
                runSpacing: Space.x12,
                children: [
                  for (final room in shown.rooms)
                    SizedBox(
                      width: width,
                      child: _RoomCard(
                        room,
                        now: now,
                        grace: today.graceMinutes,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: Space.x16),
          Text(
            'Read-only. The desk changes beds; you see them within about a '
            'minute.',
            style: t.small.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// How a status looks (docs/design.md, "Bed status styles"): never by
/// colour alone; the label always says it.
({Color fill, Color ink, Color border, bool dashed}) _style(
  LodgingColors c,
  BoardStatus s,
) => switch (s) {
  BoardStatus.occupied => (
    fill: c.marine,
    ink: c.white,
    border: c.marine,
    dashed: false,
  ),
  BoardStatus.overstay => (
    fill: c.red,
    ink: c.white,
    border: c.red,
    dashed: false,
  ),
  BoardStatus.toClean => (
    fill: c.butter,
    ink: c.butterText,
    border: c.butterBorder,
    dashed: true,
  ),
  BoardStatus.ready => (
    fill: c.white,
    ink: c.ink,
    border: c.marine,
    dashed: false,
  ),
};

Widget _box(
  LodgingColors c,
  BoardStatus s, {
  required Widget child,
  required EdgeInsets padding,
  bool thick = false,
}) {
  final st = _style(c, s);
  final inner = Container(
    padding: padding,
    decoration: BoxDecoration(
      color: st.fill,
      borderRadius: BorderRadius.circular(Radii.tile),
      border: st.dashed
          ? null
          : Border.all(
              color: thick ? c.ink : st.border,
              width: thick ? Sizes.borderStrong * 2 : Sizes.borderThin,
            ),
    ),
    child: child,
  );
  return st.dashed
      ? DashedBorder(
          color: thick ? c.ink : st.border,
          radius: Radii.tile,
          child: inner,
        )
      : inner;
}

class _CountTile extends StatelessWidget {
  const _CountTile(
    this.status,
    this.count, {
    required this.selected,
    required this.onTap,
  });

  final BoardStatus status;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final ink = _style(c, status).ink;
    return Semantics(
      button: true,
      selected: selected,
      label: '$count ${status.label}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('owner.beds.count.${status.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.tile),
        child: _box(
          c,
          status,
          thick: selected,
          padding: const EdgeInsets.all(Space.x8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$count', style: t.moneyLarge.copyWith(color: ink)),
              Text(status.label, style: t.small.copyWith(color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard(this.room, {required this.now, required this.grace});

  final BoardRoom room;
  final DateTime now;
  final int grace;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Card(
      key: ValueKey('owner.beds.room.${room.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.x10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Room ${room.number}', style: t.bodyStrong),
            for (final bed in room.beds) ...[
              const SizedBox(height: Space.x6),
              () {
                final status = statusOf(bed, now: now, graceMinutes: grace);
                final ink = _style(c, status).ink;
                return Semantics(
                  label: 'Bed ${bed.label.code}, ${status.label}',
                  excludeSemantics: true,
                  child: _box(
                    c,
                    status,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.x8,
                      vertical: Space.x6,
                    ),
                    child: Row(
                      children: [
                        Text(
                          bed.label.code,
                          style: t.bodyStrong.copyWith(color: ink),
                        ),
                        const SizedBox(width: Space.x6),
                        Flexible(
                          child: Text(
                            status.label,
                            key: ValueKey('owner.beds.bed.${bed.id}'),
                            style: t.small.copyWith(color: ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }(),
            ],
          ],
        ),
      ),
    );
  }
}
