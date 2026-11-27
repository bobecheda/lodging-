import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/desk_shell.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/focus_ring.dart';
import '../../../core/clock/clock.dart';
import '../../../core/money/kes.dart';
import '../../housekeeping/domain/housekeeping.dart';
import '../../housekeeping/presentation/housekeeping_providers.dart';
import '../../setup/domain/rooms.dart';
import '../domain/check_in_view.dart';

/// "Bed" on the v2 check-in (PR 6, Figma "Desk · Check-in (full)"): the
/// chosen bed as a row with a marine border and Change (or "Choose a bed"
/// and Choose), the reason when it can't be let any more, and the whole
/// room switch for a 2-bed room.
class CheckInBedSection extends ConsumerWidget {
  const CheckInBedSection({
    super.key,
    required this.rooms,
    required this.room,
    required this.letting,
    required this.bedProblem,
    required this.other,
    required this.wholeRoom,
    required this.onChoose,
    required this.onWholeRoom,
  });

  /// Every open room, for the chooser.
  final List<RoomSummary> rooms;

  /// The chosen bed's room, or null with no bed yet.
  final RoomSummary? room;

  /// The chosen bed, and the other bed too when the whole room is on.
  final List<BedSummary> letting;

  /// Why the chosen bed can't be let any more, if it can't.
  final String? bedProblem;

  /// The room's other bed, if it has one.
  final BedSummary? other;
  final bool wholeRoom;
  final ValueChanged<String> onChoose;
  final ValueChanged<bool> onWholeRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final room = this.room;
    final other = this.other;
    final chosen = room != null && letting.isNotEmpty;

    String? cleaned;
    if (chosen && letting.length == 1) {
      final last = ref.watch(lastCleanedProvider(letting.single.id)).value;
      if (last != null) {
        cleaned = cleanedLine(
          last.at,
          last.by,
          now: ref.watch(clockProvider).now(),
        );
      }
    }
    final swatch = chosen ? c.category(letting.first.categoryColour) : null;
    final note = room == null || other == null
        ? null
        : wholeRoomNote(room.number, other);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Bed', style: t.sectionTitle),
        const SizedBox(height: Space.x8),
        Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsetsDirectional.only(
            start: Space.x12,
            end: Space.x4,
          ),
          decoration: BoxDecoration(
            color: c.white,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(
              color: chosen ? c.marine : c.fieldBorder,
              width: chosen ? Sizes.borderStrong : Sizes.borderThin,
            ),
          ),
          child: Row(
            children: [
              if (chosen && letting.length == 1) ...[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.marineTint,
                    borderRadius: BorderRadius.circular(Radii.badge),
                  ),
                  child: Text(
                    letting.single.label.code,
                    style: t.secondaryMedium.copyWith(color: c.marine),
                  ),
                ),
                const SizedBox(width: Space.x12),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chosen
                            ? bedRowTitle(room.number, letting)
                            : 'Choose a bed',
                        key: const ValueKey('checkIn.bed'),
                        style: t.body.copyWith(color: chosen ? c.ink : c.muted),
                      ),
                      if (chosen)
                        Text(
                          bedRowMeta(letting, cleaned: cleaned),
                          key: const ValueKey('checkIn.bedMeta'),
                          style: t.meta.copyWith(color: swatch!.text),
                        ),
                    ],
                  ),
                ),
              ),
              Builder(
                builder: (anchor) => TextButton(
                  key: const ValueKey('checkIn.changeBed'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, Sizes.target),
                  ),
                  onPressed: () => _openChooser(anchor),
                  child: Text(chosen ? 'Change' : 'Choose'),
                ),
              ),
            ],
          ),
        ),
        if (bedProblem != null && room != null) ...[
          const SizedBox(height: Space.x6),
          Text(
            '${bedName(room.number, letting.first.label)} $bedProblem now. '
            'Choose another bed.',
            key: const ValueKey('checkIn.bedProblem'),
            style: t.secondary.copyWith(color: c.redText),
          ),
        ],
        if (room != null && other != null && letting.isNotEmpty) ...[
          const SizedBox(height: Space.x8),
          MergeSemantics(
            child: Row(
              children: [
                Switch(
                  key: const ValueKey('checkIn.wholeRoom'),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  value: wholeRoom && note == null,
                  onChanged: note != null || bedProblem != null
                      ? null
                      : onWholeRoom,
                ),
                const SizedBox(width: Space.x12),
                Flexible(
                  child: Text(
                    'Whole room (${room.number} A + B)',
                    style: t.body.copyWith(
                      color: note == null ? c.ink : c.muted,
                    ),
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(width: Space.x12),
                  Flexible(
                    child: Text(
                      '· $note',
                      key: const ValueKey('checkIn.wholeRoomNote'),
                      style: t.secondary.copyWith(color: c.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openChooser(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null) return;
    final screen = MediaQuery.sizeOf(anchor).width;
    final chosen = await showShellCard<String>(
      anchor,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      label: 'bed chooser',
      alignRight: true,
      cardKey: const ValueKey('checkIn.chooser'),
      width: math.min(460, screen - 2 * Space.x8),
      builder: (context) => _BedChooser(
        groups: readyBedGroups(rooms),
        chosenId: letting.isEmpty ? null : letting.first.id,
      ),
    );
    if (chosen != null) onChoose(chosen);
  }
}

/// The chooser card (Figma "Bed chooser (opens from Change)"): the Ready
/// and clean beds by category, each an 80×44 chip; the chosen one solid
/// marine.
class _BedChooser extends StatelessWidget {
  const _BedChooser({required this.groups, required this.chosenId});

  final List<ReadyBedGroup> groups;
  final String? chosenId;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    var first = true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Ready beds · ${readyBedCount(groups)}',
            key: const ValueKey('checkIn.chooser.count'),
            style: t.sectionTitle,
          ),
        ),
        if (groups.isEmpty) ...[
          const SizedBox(height: Space.x12),
          Text(
            'No bed is ready right now. Beds that need cleaning become Ready '
            'once they are cleaned.',
            key: const ValueKey('checkIn.chooser.none'),
            style: t.body.copyWith(color: c.inkSoft),
          ),
        ],
        for (final g in groups) ...[
          const SizedBox(height: Space.x14),
          Row(
            children: [
              Text(
                g.categoryName,
                style: t.secondaryMedium.copyWith(
                  color: c.category(g.colour).text,
                ),
              ),
              const SizedBox(width: Space.x8),
              Text(
                formatKes(g.pricePerNight),
                style: t.secondary.copyWith(color: c.muted),
              ),
            ],
          ),
          const SizedBox(height: Space.x8),
          Wrap(
            spacing: Space.x8,
            runSpacing: Space.x8,
            children: [
              for (final b in g.beds)
                _BedChip(
                  bed: b,
                  chosen: b.bed.id == chosenId,
                  autofocus: () {
                    final f = first;
                    first = false;
                    return f;
                  }(),
                ),
            ],
          ),
        ],
        const SizedBox(height: Space.x14),
        Text(
          'Only Ready and clean beds are listed.',
          style: t.secondary.copyWith(color: c.muted),
        ),
      ],
    );
  }
}

class _BedChip extends StatelessWidget {
  const _BedChip({
    required this.bed,
    required this.chosen,
    required this.autofocus,
  });

  final ReadyBed bed;
  final bool chosen;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Semantics(
      button: true,
      selected: chosen,
      label: 'Bed ${bed.name}',
      excludeSemantics: true,
      child: FocusRing(
        radius: Radii.control,
        child: Material(
          color: chosen ? c.marine : c.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
            side: BorderSide(color: c.marine, width: Sizes.borderStrong),
          ),
          child: InkWell(
            key: ValueKey(
              'checkIn.pick.${bed.room.number}${bed.bed.label.code}',
            ),
            autofocus: autofocus,
            borderRadius: BorderRadius.circular(Radii.control),
            onTap: () => Navigator.of(context).pop(bed.bed.id),
            child: SizedBox(
              width: 80,
              height: Sizes.target,
              child: Center(
                child: Text(
                  bed.name,
                  style: t.moneySmall.copyWith(
                    color: chosen ? c.white : c.marine,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
