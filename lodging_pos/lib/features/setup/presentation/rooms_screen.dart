import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/notes.dart';
import '../domain/rooms.dart';
import 'rooms_providers.dart';
import 'widgets/add_room_panel.dart';
import 'widgets/edit_room_panel.dart';
import 'widgets/room_table.dart';

/// AD-2 "Rooms and beds" (owner only): a table of rooms and a side panel to
/// add or edit one (artboard "Setup — rooms and beds").
class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

sealed class _Panel {
  const _Panel();
}

class _Adding extends _Panel {
  const _Adding();
}

class _Editing extends _Panel {
  const _Editing(this.roomId);
  final String roomId;
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  _Panel? _panel;

  void _close() => setState(() => _panel = null);

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final rooms = ref.watch(roomsListProvider);
    final list = rooms.value ?? const <RoomSummary>[];
    final editing = switch (_panel) {
      _Editing(:final roomId) => list.where((r) => r.id == roomId).firstOrNull,
      _ => null,
    };

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text('Rooms and beds', style: t.pageTitle),
                  ),
                  const SizedBox(height: Space.x4),
                  Text(
                    roomsSummary(list),
                    key: const ValueKey('rooms.summary'),
                    style: t.small,
                  ),
                ],
              ),
            ),
            AppButton.primary(
              key: const ValueKey('rooms.add'),
              label: 'Add room',
              icon: Icons.add_rounded,
              onPressed: () => setState(() => _panel = const _Adding()),
            ),
          ],
        ),
        const SizedBox(height: Space.x20),
        Expanded(
          child: switch (rooms) {
            AsyncError(:final error) => Align(
              alignment: Alignment.topCenter,
              child: Note.error('$error', title: 'Rooms could not be loaded.'),
            ),
            AsyncData() when list.isEmpty => const Align(
              alignment: Alignment.topCenter,
              child: Note.info(
                'No rooms yet. Use "Add room" to add the first one.',
              ),
            ),
            AsyncData() => RoomTable(
              rooms: list,
              selectedRoomId: editing?.id,
              onEdit: (room) => setState(() => _panel = _Editing(room.id)),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );

    final panel = switch (_panel) {
      _Adding() => AddRoomPanel(
        key: const ValueKey('panel.add'),
        onDone: _close,
      ),
      _Editing() when editing != null => EditRoomPanel(
        key: ValueKey('panel.edit.${editing.id}'),
        room: editing,
        onDone: _close,
      ),
      _ => null,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: main),
        if (panel != null) ...[
          const SizedBox(width: Space.x24),
          SizedBox(width: 380, child: panel),
        ],
      ],
    );
  }
}

/// "12 rooms · 18 beds active · 1 room closed". Beds count only in open
/// rooms; the closed part is left out when nothing is closed.
String roomsSummary(List<RoomSummary> rooms) {
  String plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
  final open = rooms.where((r) => r.isActive);
  final beds = open.expand((r) => r.activeBeds).length;
  final closed = rooms.length - open.length;
  return [
    plural(rooms.length, 'room'),
    '${plural(beds, 'bed')} active',
    if (closed > 0) '${plural(closed, 'room')} closed',
  ].join(' · ');
}
