import 'package:flutter/material.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/notes.dart';
import '../../domain/rooms.dart';

/// The rooms table: room, floor, bed chips, status, Edit.
class RoomTable extends StatelessWidget {
  const RoomTable({
    super.key,
    required this.rooms,
    required this.selectedRoomId,
    required this.onEdit,
  });

  final List<RoomSummary> rooms;
  final String? selectedRoomId;
  final ValueChanged<RoomSummary> onEdit;

  static const _room = 2;
  static const _floor = 2;
  static const _beds = 5;
  static const _status = 3;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);

    Widget cell(int flex, Widget child) => Expanded(flex: flex, child: child);

    final header = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x20,
        vertical: Space.x14,
      ),
      child: Row(
        children: [
          cell(_room, Text('ROOM', style: t.cardHeading)),
          cell(_floor, Text('FLOOR', style: t.cardHeading)),
          cell(_beds, Text('BEDS', style: t.cardHeading)),
          cell(_status, Text('STATUS', style: t.cardHeading)),
          const SizedBox(width: 64),
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          header,
          Divider(color: c.line),
          Expanded(
            child: ListView.separated(
              itemCount: rooms.length,
              separatorBuilder: (_, _) => Divider(color: c.lineSoft),
              itemBuilder: (context, i) {
                final room = rooms[i];
                final isSelected = room.id == selectedRoomId;
                return Container(
                  key: ValueKey('rooms.row.${room.number}'),
                  color: isSelected ? c.marineTintStrong : null,
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.x20,
                    vertical: Space.x8,
                  ),
                  child: Row(
                    children: [
                      cell(
                        _room,
                        Text('Room ${room.number}', style: t.bodyStrong),
                      ),
                      cell(
                        _floor,
                        Text(
                          room.floor ?? '—',
                          style: t.body.copyWith(color: c.inkSoft),
                        ),
                      ),
                      cell(
                        _beds,
                        Wrap(
                          spacing: Space.x8,
                          runSpacing: Space.x6,
                          children: [for (final bed in room.beds) BedChip(bed)],
                        ),
                      ),
                      cell(
                        _status,
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: room.isActive
                              ? const StatusBadge(
                                  'ACTIVE',
                                  tone: BadgeTone.active,
                                )
                              : const StatusBadge(
                                  'CLOSED · REPAIRS',
                                  tone: BadgeTone.warning,
                                ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: TextButton(
                          key: ValueKey('rooms.edit.${room.number}'),
                          onPressed: () => onEdit(room),
                          child: Text(
                            'Edit',
                            semanticsLabel: 'Edit room ${room.number}',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "A · Deluxe" on marineTint; a closed bed is greyed and says so.
class BedChip extends StatelessWidget {
  const BedChip(this.bed, {super.key});

  final BedSummary bed;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final text = bed.isActive
        ? '${bed.label.code} · ${bed.categoryName}'
        : '${bed.label.code} · closed';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x8,
        vertical: Space.x4,
      ),
      decoration: BoxDecoration(
        color: bed.isActive ? c.marineTint : c.lineSoft,
        borderRadius: BorderRadius.circular(Radii.badge),
      ),
      child: Text(
        text,
        style: t.smallStrong.copyWith(color: bed.isActive ? c.marine : c.muted),
      ),
    );
  }
}
