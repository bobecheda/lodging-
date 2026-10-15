import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/buttons.dart';
import '../../../../app/widgets/labeled_dropdown.dart';
import '../../../../app/widgets/labeled_field.dart';
import '../../../../app/widgets/notes.dart';
import '../../../../core/auth/session.dart';
import '../../domain/rooms.dart';
import '../rooms_providers.dart';
import 'panel_parts.dart';

/// Edits one room: number, floor and bed categories saved together
/// (`room.update` + `bed.update`); bed and room open/close actions apply at
/// once, each blocked with its reason when a rule forbids it.
class EditRoomPanel extends ConsumerStatefulWidget {
  const EditRoomPanel({super.key, required this.room, required this.onDone});

  final RoomSummary room;
  final VoidCallback onDone;

  @override
  ConsumerState<EditRoomPanel> createState() => _EditRoomPanelState();
}

class _EditRoomPanelState extends ConsumerState<EditRoomPanel> {
  late final _number = TextEditingController(text: widget.room.number);
  late final _floor = TextEditingController(text: widget.room.floor ?? '');

  /// Category picks not yet saved; beds not listed keep their current one.
  final _categories = <BedLabel, String>{};
  String? _newBedCategory;
  var _errors = <RoomField, String>{};
  String? _error;
  var _busy = false;

  RoomSummary get room => widget.room;

  @override
  void dispose() {
    _number.dispose();
    _floor.dispose();
    super.dispose();
  }

  /// Runs a write, reloads the rooms, and shows any rule message.
  Future<void> _run(Future<void> Function() write, {bool close = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await write();
      ref.invalidate(roomsListProvider);
      if (close) widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is InvalidRoom) _errors = e.errors;
        _error = panelError(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    final numberProblem = roomNumberError(_number.text);
    setState(() => _errors = {RoomField.number: ?numberProblem});
    if (numberProblem != null) return;
    _run(
      () => ref
          .read(roomsRepositoryProvider)
          .updateRoom(
            ref.read(sessionProvider)!,
            room.id,
            RoomEdit(
              number: _number.text,
              floor: _floor.text,
              notes: room.notes,
              bedCategories: {
                for (final bed in room.beds)
                  bed.label: _categories[bed.label] ?? bed.categoryId,
              },
            ),
          ),
      close: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final repo = ref.read(roomsRepositoryProvider);
    final owner = ref.watch(sessionProvider)!;
    final categories = ref.watch(bedCategoriesProvider).value ?? const [];
    final roomBlocker = room.isActive
        ? deactivateRoomBlocker(room)
        : reactivateRoomBlocker(room);
    final canAddBed = addBedBlocker(room) == null;

    return SidePanel(
      title: 'Edit Room ${room.number}',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Room number',
                controller: _number,
                fieldKey: const ValueKey('edit.number'),
                errorText: _errors[RoomField.number],
              ),
            ),
            const SizedBox(width: Space.x12),
            Expanded(
              child: LabeledField(
                label: 'Floor (optional)',
                controller: _floor,
                fieldKey: const ValueKey('edit.floor'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x20),
        Text('Beds in this room (1 or 2)', style: t.fieldLabel),
        const SizedBox(height: Space.x8),
        for (final bed in room.beds)
          _BedCard(
            bed: bed,
            room: room,
            category: _categories[bed.label] ?? bed.categoryId,
            options: categoryOptions(categories, current: bed.categoryId),
            busy: _busy,
            onCategory: (id) => setState(() => _categories[bed.label] = id),
            onDeactivate: () => _run(() => repo.deactivateBed(owner, bed.id)),
            onReactivate: () => _run(() => repo.reactivateBed(owner, bed.id)),
          ),
        if (canAddBed) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: LabeledDropdown<String>(
                  fieldKey: const ValueKey('edit.newBedCategory'),
                  label: 'Add bed B',
                  options: categoryOptions(categories),
                  value: _newBedCategory,
                  onChanged: (v) => setState(() => _newBedCategory = v),
                ),
              ),
              const SizedBox(width: Space.x12),
              AppButton.secondary(
                key: const ValueKey('edit.addBed'),
                label: 'Add bed',
                onPressed: _newBedCategory == null || _busy
                    ? null
                    : () => _run(
                        () => repo.addBed(owner, room.id, _newBedCategory!),
                      ),
              ),
            ],
          ),
          const SizedBox(height: Space.x12),
        ],
        Text(
          'Changing a category affects new check-ins only. Guests already '
          'staying keep their price.',
          style: t.small,
        ),
        const SizedBox(height: Space.x16),
        if (_error != null) ...[
          Note.error(_error!),
          const SizedBox(height: Space.x16),
        ],
        Row(
          children: [
            Expanded(
              child: AppButton.primary(
                key: const ValueKey('edit.save'),
                label: 'Save room',
                busy: _busy,
                onPressed: _save,
              ),
            ),
            const SizedBox(width: Space.x12),
            AppButton.secondary(
              key: const ValueKey('edit.cancel'),
              label: 'Cancel',
              onPressed: widget.onDone,
            ),
          ],
        ),
        const SizedBox(height: Space.x20),
        const Divider(),
        const SizedBox(height: Space.x16),
        if (room.isActive)
          AppButton.destructive(
            key: const ValueKey('edit.closeRoom'),
            label: 'Close room for repairs',
            onPressed: roomBlocker != null || _busy
                ? null
                : () => _run(() => repo.deactivateRoom(owner, room.id)),
          )
        else ...[
          AppButton.secondary(
            key: const ValueKey('edit.reopenRoom'),
            label: 'Reopen room',
            onPressed: roomBlocker != null || _busy
                ? null
                : () => _run(() => repo.reactivateRoom(owner, room.id)),
          ),
          const SizedBox(height: Space.x8),
          Text('Its beds come back as needing cleaning.', style: t.small),
        ],
        if (roomBlocker != null) ...[
          const SizedBox(height: Space.x8),
          Note.error(roomBlocker, key: const ValueKey('edit.roomBlocker')),
        ],
      ],
    );
  }
}

class _BedCard extends StatelessWidget {
  const _BedCard({
    required this.bed,
    required this.room,
    required this.category,
    required this.options,
    required this.busy,
    required this.onCategory,
    required this.onDeactivate,
    required this.onReactivate,
  });

  final BedSummary bed;
  final RoomSummary room;
  final String? category;
  final List<DropdownOption<String>> options;
  final bool busy;
  final ValueChanged<String> onCategory;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final code = bed.label.code;
    final blocker = bed.isActive ? deactivateBedBlocker(bed, room) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: Space.x12),
      padding: const EdgeInsets.all(Space.x14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BedLetter(bed.label),
              const SizedBox(width: Space.x12),
              Expanded(
                child: LabeledDropdown<String>(
                  fieldKey: ValueKey('edit.bed$code'),
                  label: 'Category',
                  options: options,
                  value: category,
                  onChanged: onCategory,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x8),
          if (bed.isActive)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: ValueKey('edit.deactivate$code'),
                onPressed: blocker != null || busy ? null : onDeactivate,
                style: TextButton.styleFrom(foregroundColor: c.redText),
                child: Text('Deactivate Bed $code'),
              ),
            )
          else
            Wrap(
              spacing: Space.x12,
              runSpacing: Space.x8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const StatusBadge('CLOSED · REPAIRS', tone: BadgeTone.warning),
                TextButton(
                  key: ValueKey('edit.reactivate$code'),
                  onPressed: busy ? null : onReactivate,
                  child: Text('Reactivate Bed $code'),
                ),
              ],
            ),
          if (blocker != null)
            Note.error(blocker, key: ValueKey('edit.bedBlocker$code')),
          if (!bed.isActive)
            Text('It comes back as needing cleaning.', style: t.small),
        ],
      ),
    );
  }
}
